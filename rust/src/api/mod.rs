pub mod disputes;
pub mod identity;
pub mod messages;
pub mod nostr;
pub mod orders;
pub mod types;

pub fn get_app_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}
