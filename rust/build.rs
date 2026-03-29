fn main() {
    // Tell Cargo to re-run this build script if source changes.
    // Cargokit integration (in rust_builder/) handles the Flutter-side build hooks.
    println!("cargo:rerun-if-changed=src/");
    println!("cargo:rerun-if-changed=build.rs");
}
