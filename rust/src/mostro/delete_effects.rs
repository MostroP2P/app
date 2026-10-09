//! The non-store side effects of an identity deletion, as a seam (#553).
//!
//! The real ones touch process-wide state — relay subscriptions, push
//! registrations, the in-memory stores — so the wiring test in
//! `api::identity` injects doubles instead of reaching them from the
//! parallel suite. Outside `crate::api`, flutter_rust_bridge never scans it;
//! inside, it would need `#[frb(ignore)]` like `api::push::PushServer`.

/// What [`crate::api::identity::delete_identity`] must do besides wiping the
/// identity's rows from the store it is handed. `unregister_push` writes
/// too: the push registrations, in the application database.
pub(crate) trait DeleteEffects {
    /// Give back the identity's relay subscriptions — first, while the
    /// identity still exists (the lifecycle test pins that).
    async fn release_identity_subscriptions(&self);
    /// Stop the push server waking this device for keys no longer held.
    async fn unregister_push(&self);
    /// Empty the process-wide in-memory stores
    /// ([`crate::api::identity::forget_identity_state`]).
    async fn forget_identity_state(&self);
}

pub(crate) struct RealDeleteEffects;

impl DeleteEffects for RealDeleteEffects {
    async fn release_identity_subscriptions(&self) {
        crate::api::orders::release_identity_subscriptions().await;
    }
    async fn unregister_push(&self) {
        crate::api::push::unregister_all().await;
    }
    async fn forget_identity_state(&self) {
        crate::api::identity::forget_identity_state().await;
    }
}

#[cfg(test)]
mod tests {
    use crate::source_guard::{expect_body, item_body, mutant, production_code};

    const RELEASE: &str = "crate::api::orders::release_identity_subscriptions().await;";
    const PUSH: &str = "crate::api::push::unregister_all().await;";
    const FORGET: &str = "crate::api::identity::forget_identity_state().await;";

    /// Each production effect is exactly its own cleanup: one method per
    /// call, read per method so two bodies cannot trade places.
    fn check_real_effects(source: &str) -> Result<(), String> {
        let code = item_body(
            &production_code(source),
            "impl DeleteEffects for RealDeleteEffects",
        )?;
        expect_body(
            &code,
            "async fn release_identity_subscriptions(&self)",
            RELEASE,
        )?;
        expect_body(&code, "async fn unregister_push(&self)", PUSH)?;
        expect_body(&code, "async fn forget_identity_state(&self)", FORGET)
    }

    /// The production effects are one-liners the wiring test's doubles
    /// cannot see: emptying one would leave that test green (#553). Same
    /// source-level guard as `forgetting_the_identity_runs_every_reset`, one
    /// level above it.
    #[test]
    fn the_real_delete_effects_reach_the_real_cleanups() {
        check_real_effects(include_str!("delete_effects.rs")).unwrap();
    }

    /// The guard above, against the mutants that used to pass it (PR #565
    /// review): each one must be refused.
    #[test]
    fn the_effects_guard_refuses_a_disconnected_cleanup() {
        let source = include_str!("delete_effects.rs");
        // The bodies of the first and last effect traded: in production the
        // in-memory stores would be emptied while the old keys still listen.
        let swapped = mutant(source, RELEASE, "SWAP");
        let swapped = mutant(&swapped, FORGET, RELEASE);
        let swapped = mutant(&swapped, "SWAP", FORGET);
        assert!(check_real_effects(&swapped).is_err());

        for call in [RELEASE, PUSH, FORGET] {
            let commented = mutant(source, call, &format!("// {call}"));
            assert!(
                check_real_effects(&commented).is_err(),
                "commenting out {call} must fail the guard",
            );
        }
    }
}
