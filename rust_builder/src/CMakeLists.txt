# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(rust_library VERSION 0.0.1 LANGUAGES C)

add_library(rust SHARED
  "rust.c"
)

set_target_properties(rust PROPERTIES
  PUBLIC_HEADER rust.h
  OUTPUT_NAME "rust"
)

target_compile_definitions(rust PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(rust PRIVATE "-Wl,-z,max-page-size=16384")
endif()
