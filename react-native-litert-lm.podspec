require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name         = 'react-native-litert-lm'
  s.version      = package['version']
  s.summary      = package['description']
  s.homepage     = 'https://github.com/Medforall/react-native-litert-lm'
  s.license      = package['license']
  s.author       = 'MedForAll Engineering'
  s.source       = { :git => 'https://github.com/Medforall/react-native-litert-lm.git', :tag => s.version }
  s.platforms    = { :ios => '17.0' }

  s.source_files = 'ios/LiteRTLM/**/*.{swift,h,m}'
  s.vendored_libraries = 'ios/Vendor/libLiteRTLM.a'
  s.preserve_paths = 'ios/Vendor/include/**/*.h', 'ios/Vendor/prebuilt/**/*'

  # Pod target: compiler/header settings only (no linker flags — static lib targets don't run ld)
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/ios/Vendor/include"',
    'SWIFT_INCLUDE_PATHS' => '"$(PODS_TARGET_SRCROOT)/ios/Vendor/include"',
  }

  # App target: linker flags (this is where ld runs and -force_load takes effect)
  # -force_load ensures C++ static initializers in engine_impl.o are preserved
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-lc++ -lz -force_load "${PODS_ROOT}/../../node_modules/@medforall/react-native-litert-lm/ios/Vendor/libLiteRTLM.a"',
  }

  s.dependency 'React-Core'
end
