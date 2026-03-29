pub mod identity;
pub mod types;

pub fn get_app_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}
