import Cocoa
import PostHog

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        let config = PostHogConfig(
            apiKey: "_6SG-F7I1vCuZ-HdJL3VZQqjBlaSb1_20hDPwqMNnGI"
        )
        config.debug = true

        PostHogSDK.shared.setup(config)
//        PostHogSDK.shared.capture("Event from MacOS example!")
    }

    func applicationWillTerminate(_: Notification) {
        // Insert code here to tear down your application
    }
}
