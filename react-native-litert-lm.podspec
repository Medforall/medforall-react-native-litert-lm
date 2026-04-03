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

  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/ios/Vendor/include"',
    'OTHER_LDFLAGS' => '-lc++',
    'SWIFT_INCLUDE_PATHS' => '"$(PODS_TARGET_SRCROOT)/ios/Vendor/include"',
  }

  s.dependency 'React-Core'
end
