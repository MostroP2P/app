cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "rust")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
# Six levels, not two, unlike linux/: Flutter builds this plugin through the
# junction windows/flutter/ephemeral/.plugin_symlinks/rust, and Windows
# collapses the `..` lexically before following it, so `../../rust` lands on
# rust_builder/ itself ("Cannot open file rust_builder\Cargo.toml"). Counted
# from that junction, this reaches the repository root. Same as the
# flutter_rust_bridge template (frb_example/flutter_via_create).
apply_cargokit(${PROJECT_NAME} ../../../../../../rust rust "")

set(rust_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
