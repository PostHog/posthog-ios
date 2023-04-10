Pod::Spec.new do |s|
  s.name             = "PostHog"
  s.version          = "2.0.2"
  s.summary          = "The hassle-free way to add posthog to your iOS app."

  s.description      = <<-DESC
                       PostHog for iOS provides a single API that lets you
                       integrate with over 100s of tools.
                       DESC

  s.homepage         = "http://posthog.com/"
  s.license          =  { :type => 'MIT' }
  s.author           = { "PostHog" => "tim@posthog.com" }
  s.source           = { :git => "https://github.com/PostHog/posthog-ios.git", :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/PostHogHQ'

  s.ios.deployment_target = '9.0'
  s.tvos.deployment_target = '9.0'

  s.ios.frameworks = 'CoreTelephony'
  s.frameworks = 'Security', 'StoreKit', 'SystemConfiguration', 'UIKit'
  s.vendored_frameworks = "PostHogRecorder.xcframework"
  
  s.source_files = [
    'PostHog/Classes/**/*',
    'PostHog/Internal/**/*',
    'PostHog/Vendor/**/*'
  ]
end
