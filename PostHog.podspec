Pod::Spec.new do |s|
  s.name             = "PostHog"
  s.version          = "3.6.1"
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
  s.swift_versions = "5.3"

  s.frameworks = 'Foundation'

  s.source_files = [
    'PostHog/**/*.{swift,h,hpp,m,mm,c,cpp}'
  ]
  s.resource_bundles = { "PostHog" => "PostHog/Resources/PrivacyInfo.xcprivacy" }
end
