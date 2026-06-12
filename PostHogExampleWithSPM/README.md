# Example with SPM

This is an example of how to use the PostHog iOS SDK with SPM.

## Installation

1. Install Xcode if you haven't already:

Follow steps from the [Xcode docs](https://developer.apple.com/xcode/resources/).

## Add a SP dependency to the project via Xcode

1. Click on the project in the Project Navigator.
2. Select the project in the Project and Targets list.
3. Select the General tab.
4. Scroll down to the Frameworks and Libraries section.
5. Click the + button.
6. Click Add Other...
7. Click Add Package Dependency
8. Enter the URL of the PostHog SDK repo or the local path to the repo.

## Import the PostHog package

```swift
import PostHog
```

And run the project.
