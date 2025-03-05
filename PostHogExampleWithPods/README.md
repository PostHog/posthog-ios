# Example with CocoaPods

This is an example of how to use the PostHog iOS SDK with CocoaPods.

## Installation

1. Install CocoaPods if you haven't already:

<!-- https://cocoapods.org/#install -->

```bash
sudo gem install cocoapods
```

## Add a Podfile to the project

<!-- https://guides.cocoapods.org/using/using-cocoapods.html#installation -->

```text
platform :ios, '16.0'

use_frameworks!

target '$your_project' do
  pod 'PostHog', '~> 3.0'
end
```

Replace `$your_project` to your project name.

## Run `pod install`

```bash
pod install
```

## Open the project

Always open the `*.xcworkspace` file, not the `*.xcodeproj` file.
