Pod::Spec.new do |s|
  s.name             = "PostHog"
  s.version          = "3.55.0"
  s.summary          = "The hassle-free way to add posthog to your iOS app."

  s.description      = <<-DESC
                       PostHog for iOS provides a single API that lets you
                       integrate with over 100s of tools.
                       DESC

  s.homepage         = "http://posthog.com/"
  s.license          =  { :type => 'MIT' }
  s.author           = { "PostHog" => "engineering@posthog.com" }
  s.source           = { :git => "https://github.com/PostHog/posthog-ios.git", :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/PostHog'
  s.readme           = "https://raw.githubusercontent.com/PostHog/posthog-ios/#{s.version.to_s}/README.md"
  s.changelog        = "https://raw.githubusercontent.com/PostHog/posthog-ios/#{s.version.to_s}/CHANGELOG.md"

  s.ios.deployment_target = '13.0'
  s.tvos.deployment_target = '13.0'
  s.osx.deployment_target = "10.15"
  s.watchos.deployment_target = "6.0"
  s.visionos.deployment_target = "1.0"
  s.swift_versions = "5.3"

  s.frameworks = 'Foundation'

  # Vendored PLCrashReporter source (not available on watchOS/visionOS)
  s.libraries = 'c++'
  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '-lc++',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) PLCR_PRIVATE PLCF_RELEASE_BUILD SWIFT_PACKAGE',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/vendor/PHPLCrashReporter/Dependencies/protobuf-c" "${PODS_TARGET_SRCROOT}/vendor/PHPLCrashReporter/Dependencies/protobuf-c/protobuf-c" "${PODS_TARGET_SRCROOT}/vendor/PHPLCrashReporter/Source"'
  }

  s.source_files = [
    'PostHog/**/*.{swift,h,hpp,m,mm,c,cpp}',
    'vendor/libwebp/**/*.{h,c}',
    'vendor/PHPLCrashReporter/Source/**/*.{h,m,mm,c,cpp,S}',
    'vendor/PHPLCrashReporter/Dependencies/protobuf-c/**/*.h',
    'vendor/PHPLCrashReporter/Dependencies/protobuf-c/**/*.c'
  ]

  # Crash reporting is not supported on watchOS/visionOS
  s.watchos.exclude_files = [
    'vendor/PHPLCrashReporter/Source/**/*',
    'vendor/PHPLCrashReporter/Dependencies/**/*'
  ]
  s.visionos.exclude_files = [
    'vendor/PHPLCrashReporter/Source/**/*',
    'vendor/PHPLCrashReporter/Dependencies/**/*'
  ]
  s.exclude_files = [
    'vendor/PHPLCrashReporter/Source/PLCrashReport.proto'
  ]
  s.resource_bundles = {
    'PostHog' => 'PostHog/Resources/PrivacyInfo.xcprivacy',
    'PHPLCrashReporter' => 'vendor/PHPLCrashReporter/Resources/PrivacyInfo.xcprivacy'
  }
  
  # Include the upload script for dSYM uploads
  s.preserve_paths = ['build-tools/upload-symbols.sh', 'vendor/PLCrashReporter-LICENSE.txt', 'vendor/PHPLCrashReporter/LICENSE']
end
