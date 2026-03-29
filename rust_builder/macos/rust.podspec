Pod::Spec.new do |s|
  s.name             = 'rust'
  s.version          = '0.0.1'
  s.summary          = 'Mostro Mobile v2 — Rust core library (flutter_rust_bridge + cargokit)'
  s.homepage         = 'https://github.com/MostroP2P/mostro-mobile'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mostro' => 'info@mostro.network' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.14'

  s.script_phase = {
    :name => 'Build Rust library',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../rust rust',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ["${BUILT_PRODUCTS_DIR}/librust.a"],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/librust.a',
  }
  s.swift_version = '5.0'
end
