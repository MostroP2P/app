//! Wire-form contract for the Cashu escrow messages (phase C0).
//!
//! `docs/cashu/README.md` §2 describes the JSON this client must exchange with
//! a Cashu-mode `mostrod`, but it was written before the dependency landed and
//! says so: *"casing to be confirmed against `mostro-core` 0.14 serde
//! attributes during Phase C0"*. This module is that confirmation, kept as
//! tests rather than prose so the contract cannot drift silently when
//! `mostro-core` is next bumped — a rename upstream fails here instead of at
//! runtime against a live daemon.
//!
//! Test-only: it defines no runtime API.
//!
//! What is pinned here is exactly what `mostro-core` defines, and no more.
//! The **escrow request** (Mostro → seller after a take) has no type of its
//! own: it rides on `SmallOrder`, which names the order's mint since 0.17.1 —
//! see the last test in this file.

#[cfg(test)]
mod tests {
    use mostro_core::prelude::*;

    /// `Action` serializes kebab-case, so the Cashu actions appear on the wire
    /// exactly as `docs/cashu/README.md` §2 shows them.
    #[test]
    fn cashu_actions_are_kebab_case() {
        // Arrange / Act
        let add = serde_json::to_string(&Action::AddCashuEscrow).unwrap();
        let locked = serde_json::to_string(&Action::CashuEscrowLocked).unwrap();
        let pm_sig = serde_json::to_string(&Action::CashuPmSignature).unwrap();

        // Assert
        assert_eq!(add, "\"add-cashu-escrow\"");
        assert_eq!(locked, "\"cashu-escrow-locked\"");
        assert_eq!(pm_sig, "\"cashu-pm-signature\"");
    }

    /// The lock proof's field names are the daemon's contract: every one of
    /// them is read by `mostrod` when it validates the 2-of-3 condition.
    #[test]
    fn lock_proof_serializes_with_the_documented_field_names() {
        // Arrange
        let proof = CashuLockProof::new(
            "cashuBo2Ftd2h0dHBz".to_string(),
            "https://mint.example.com".to_string(),
            "9f3a".to_string(),
            "77b2".to_string(),
            "dbe0".to_string(),
        )
        .with_fee_token("cashuBfee".to_string());

        // Act
        let value: serde_json::Value = serde_json::from_str(&proof.as_json().unwrap()).unwrap();

        // Assert
        assert_eq!(value["token"], "cashuBo2Ftd2h0dHBz");
        assert_eq!(value["mint_url"], "https://mint.example.com");
        assert_eq!(value["buyer_pubkey"], "9f3a");
        assert_eq!(value["seller_pubkey"], "77b2");
        assert_eq!(value["mostro_pubkey"], "dbe0");
        assert_eq!(value["fee_token"], "cashuBfee");
    }

    /// `fee_token` is `skip_serializing_if = "Option::is_none"`, so a node that
    /// charges no fee produces the pre-0.14 wire form byte-for-byte. Worth
    /// pinning: it is what lets a 0.14 client talk to an older daemon.
    #[test]
    fn lock_proof_omits_absent_fee_token_entirely() {
        // Arrange
        let proof = CashuLockProof::new(
            "cashuBtoken".to_string(),
            "https://mint.example.com".to_string(),
            "9f3a".to_string(),
            "77b2".to_string(),
            "dbe0".to_string(),
        );

        // Act
        let json = proof.as_json().unwrap();

        // Assert — absent, not null.
        assert!(
            !json.contains("fee_token"),
            "fee_token must be omitted: {json}"
        );
        let back = CashuLockProof::from_json(&json).unwrap();
        assert_eq!(back.fee_token, None);
    }

    /// `Payload` is `rename_all = "snake_case"`, so the variant name is the
    /// JSON discriminator: `cashu_lock_proof`, not `CashuLockProof`.
    #[test]
    fn payload_variants_use_snake_case_discriminators() {
        // Arrange
        let lock = Payload::CashuLockProof(CashuLockProof::new(
            "t".to_string(),
            "https://mint.example.com".to_string(),
            "b".to_string(),
            "s".to_string(),
            "m".to_string(),
        ));
        let sigs = Payload::CashuSignatures(vec![CashuProofSignature::new(
            "secret-1".to_string(),
            "sig-1".to_string(),
        )]);

        // Act
        let lock_json: serde_json::Value =
            serde_json::from_str(&serde_json::to_string(&lock).unwrap()).unwrap();
        let sigs_json: serde_json::Value =
            serde_json::from_str(&serde_json::to_string(&sigs).unwrap()).unwrap();

        // Assert
        assert!(
            lock_json.get("cashu_lock_proof").is_some(),
            "got {lock_json}"
        );
        assert!(
            sigs_json.get("cashu_signatures").is_some(),
            "got {sigs_json}"
        );
        assert_eq!(sigs_json["cashu_signatures"][0]["secret"], "secret-1");
        assert_eq!(sigs_json["cashu_signatures"][0]["signature"], "sig-1");
    }

    /// The full message the seller publishes, matching the example in
    /// `docs/cashu/README.md` §2 field for field — including the `order`
    /// envelope that `Message` adds and the `version` stamp that
    /// `MessageKind::new` puts on every message. Both are part of what the
    /// daemon parses, so serializing the bare `MessageKind` would pin less
    /// than the doc shows.
    #[test]
    fn add_cashu_escrow_message_matches_the_documented_example() {
        // Arrange
        let order_id = uuid::Uuid::parse_str("ede61c96-4c13-4519-bf3a-dcf7f1e9d842").unwrap();
        let message = Message::Order(MessageKind::new(
            Some(order_id),
            Some(981234),
            Some(7),
            Action::AddCashuEscrow,
            Some(Payload::CashuLockProof(CashuLockProof::new(
                "cashuBo2Ftd2h0dHBz".to_string(),
                "https://mint.example.com".to_string(),
                "9f3a".to_string(),
                "77b2".to_string(),
                "dbe0".to_string(),
            ))),
        ));

        // Act
        let value: serde_json::Value = serde_json::from_str(&message.as_json().unwrap()).unwrap();

        // Assert — the daemon-facing envelope, then the body.
        let order = &value["order"];
        assert!(order.is_object(), "expected an `order` envelope: {value}");
        // `PROTOCOL_VER` — 2 since the transport-v2 migration, not the 1 the
        // pre-0.14 examples carried.
        assert_eq!(order["version"], 2);
        assert_eq!(order["action"], "add-cashu-escrow");
        assert_eq!(order["id"], "ede61c96-4c13-4519-bf3a-dcf7f1e9d842");
        assert_eq!(order["request_id"], 981234);
        assert_eq!(order["trade_index"], 7);
        assert_eq!(
            order["payload"]["cashu_lock_proof"]["mint_url"],
            "https://mint.example.com"
        );
    }

    /// `MessageKind::verify` is the daemon's admission rule. Pinning it here
    /// means a malformed lock is caught by our own tests rather than by a
    /// silent daemon-side rejection.
    #[test]
    fn verify_requires_an_order_id_and_the_right_payload() {
        // Arrange
        let lock = || {
            Some(Payload::CashuLockProof(CashuLockProof::new(
                "t".to_string(),
                "https://mint.example.com".to_string(),
                "b".to_string(),
                "s".to_string(),
                "m".to_string(),
            )))
        };

        // Act / Assert — the happy shape.
        let ok = MessageKind::new(
            Some(uuid::Uuid::new_v4()),
            Some(1),
            Some(0),
            Action::AddCashuEscrow,
            lock(),
        );
        assert!(ok.verify());

        // Without an order id it is not a valid escrow lock.
        let no_id = MessageKind::new(None, Some(1), Some(0), Action::AddCashuEscrow, lock());
        assert!(!no_id.verify());

        // Nor with a payload that is not a lock proof.
        let wrong_payload = MessageKind::new(
            Some(uuid::Uuid::new_v4()),
            Some(1),
            Some(0),
            Action::AddCashuEscrow,
            Some(Payload::Amount(100)),
        );
        assert!(!wrong_payload.verify());
    }

    /// A dispute payout must carry at least one signature: SIG_INPUTS needs
    /// one per proof, so an empty vector can never be spendable.
    #[test]
    fn pm_signature_rejects_an_empty_signature_set() {
        // Arrange / Act
        let empty = MessageKind::new(
            Some(uuid::Uuid::new_v4()),
            Some(1),
            None,
            Action::CashuPmSignature,
            Some(Payload::CashuSignatures(vec![])),
        );
        let one = MessageKind::new(
            Some(uuid::Uuid::new_v4()),
            Some(1),
            None,
            Action::CashuPmSignature,
            Some(Payload::CashuSignatures(vec![CashuProofSignature::new(
                "secret".to_string(),
                "sig".to_string(),
            )])),
        );

        // Assert
        assert!(!empty.verify());
        assert!(one.verify());
    }

    /// **The escrow request names the order's mint, and nothing else Cashu.**
    ///
    /// `docs/cashu/README.md` risk #1 asked how the "Mostro → seller" escrow
    /// request reaches the client. Resolved in C0 by reading the daemon
    /// (`show_cashu_escrow_request` in `src/util.rs`): it reuses types that
    /// already exist.
    ///
    /// - seller ← `Action::WaitingSellerToPay` + `Payload::Order(SmallOrder)`,
    ///   with `status = WaitingPayment`, both trade pubkeys set and
    ///   `buyer_invoice = None`;
    /// - buyer  ← `Action::WaitingSellerToPay` with **no** payload.
    ///
    /// Since MostroP2P/mostro#1047 (mostro-core 0.17.1) the maker picks the
    /// mint, so `SmallOrder` carries `cashu_mint_url` and the request names the
    /// order's mint. It is omitted while `None`, which keeps a Lightning
    /// order's wire form unchanged. `P_M` and the locktime still come from the
    /// node (the known Mostro pubkey, the 38385 tags), so C5 still classifies
    /// by payload shape (§4.4).
    ///
    /// Should upstream add the token or the lock time to `SmallOrder`, this
    /// fails — the signal to re-read the daemon before touching C5.
    #[test]
    fn escrow_request_names_the_order_mint_and_nothing_else_cashu() {
        // Arrange — a SmallOrder as it travels inside Payload::Order.
        let lightning = SmallOrder::default();
        let cashu = SmallOrder {
            cashu_mint_url: Some("https://mint.example.com".to_string()),
            ..SmallOrder::default()
        };

        // Act
        let lightning: serde_json::Value =
            serde_json::from_str(&serde_json::to_string(&lightning).unwrap()).unwrap();
        let cashu: serde_json::Value =
            serde_json::from_str(&serde_json::to_string(&cashu).unwrap()).unwrap();

        // Assert — the mint travels only when set; the rest stays daemon-side.
        assert!(
            lightning.get("cashu_mint_url").is_none(),
            "a Lightning order's wire form must not change",
        );
        assert_eq!(cashu["cashu_mint_url"], "https://mint.example.com");
        for value in [&lightning, &cashu] {
            assert!(
                value.get("cashu_escrow_token").is_none(),
                "SmallOrder now carries cashu_escrow_token — revisit C5",
            );
            assert!(
                value.get("cashu_escrow_locked_at").is_none(),
                "SmallOrder now carries cashu_escrow_locked_at — revisit C5",
            );
        }
    }
}
