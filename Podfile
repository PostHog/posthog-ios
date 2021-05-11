def shared_testing_pods
    pod 'Quick', '~> 1.2.0'
    pod 'Nimble', '~> 9.2.0'
    pod 'Nocilla', '~> 0.11.0'
    pod 'Alamofire', '~> 4.5'
    pod 'Alamofire-Synchronous', '~> 4.0'
end

target 'PostHogTests' do
    platform :ios, '11'
    use_frameworks!
    shared_testing_pods
end

target 'PostHogTestsTVOS' do
  platform :tvos
  use_frameworks!
  shared_testing_pods
end
