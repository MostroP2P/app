pub mod bond;
pub mod disputes;
pub mod escrow;
pub mod identity;
pub mod logging;
pub mod messages;
pub mod nostr;
pub mod nwc;
pub mod orders;
pub mod reputation;
pub mod settings;
pub mod types;

pub fn get_app_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Initialise the persistent store.
///
/// Must be called once on app startup **before** taking orders or sending
/// invoices.  On native platforms pass the absolute path to the SQLite file
/// (e.g. `<app_documents_dir>/mostro.db`).  On WASM `path` is used as the
/// IndexedDB database name.
///
/// Subsequent calls are no-ops.
pub async fn init_db(path: String) -> anyhow::Result<()> {
    crate::db::app_db::init_db(&path).await
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The pubspec version, without the `+build` suffix.
    ///
    /// `include_str!` rather than reading the file at runtime: the path is
    /// resolved against this source file, so the assertion holds regardless of
    /// the working directory the test happens to run from.
    fn pubspec_version() -> String {
        let pubspec = include_str!("../../../pubspec.yaml");
        let line = pubspec
            .lines()
            .find(|l| l.starts_with("version:"))
            .expect("pubspec.yaml has no top-level `version:` line");
        line.trim_start_matches("version:")
            .trim()
            .split('+')
            .next()
            .unwrap()
            .to_string()
    }

    /// `get_app_version` is what `min_version` / `max_version` announcement
    /// bounds compare against and what the About screen shows, so the crate
    /// version and the shipped app version must be the same number. They live
    /// in two files that nothing else keeps in step — this is what notices when
    /// one is bumped and the other is not.
    #[test]
    fn app_version_matches_pubspec() {
        assert_eq!(
            get_app_version(),
            pubspec_version(),
            "rust/Cargo.toml `version` and pubspec.yaml `version` have drifted; \
             bump both in the same commit"
        );
    }

    /// The build number belongs to the store listing, not to version
    /// comparison: semver excludes build metadata from precedence, so a bound
    /// carrying one would silently compare equal to one without.
    #[test]
    fn app_version_carries_no_build_number() {
        assert!(!get_app_version().contains('+'));
    }
}
