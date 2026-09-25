//! The non-store side effects of an identity deletion, as a seam (#553).
//!
//! The real ones touch process-wide state — relay subscriptions, push
//! registrations, the in-memory stores — so the wiring test in
//! `api::identity` injects doubles instead of reaching them from the
//! parallel suite. Lives outside `crate::api` on purpose: flutter_rust_bridge
//! scans only that module, and a trait there ends up half-parsed in the
//! generated headers (same reason `db::Storage` lives where it does).

/// What [`crate::api::identity::delete_identity`] must do besides the
/// database writes. Same `async fn` discipline as [`crate::db::Storage`]:
/// both implementors return `Send` futures.
#[allow(async_fn_in_trait)]
pub(crate) trait DeleteEffects {
    /// Give back the identity's relay subscriptions — first, while the
    /// identity still exists, so nothing of the old user's keeps arriving.
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
    /// The production effects are one-liners the wiring test's doubles
    /// cannot see: emptying one would leave that test green (#553). Same
    /// source-level guard as `forgetting_the_identity_empties_every_in_memory_store`,
    /// one level above it.
    #[test]
    fn the_real_delete_effects_reach_the_real_cleanups() {
        let source = include_str!("delete_effects.rs");
        let start = source
            .find("impl DeleteEffects for RealDeleteEffects")
            .expect("the production effects exist");
        let body = &source[start..start + source[start..].find("\n}\n").expect("it ends")];

        assert!(body.contains("orders::release_identity_subscriptions().await"));
        assert!(body.contains("push::unregister_all().await"));
        assert!(body.contains("identity::forget_identity_state().await"));
    }
}
