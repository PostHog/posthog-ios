import Cocoa
import PostHog

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        let config = PostHogConfig(
            apiKey: "phc_QFbR1y41s5sxnNTZoyKG2NJo2RlsCIWkUfdpawgb40D"
        )
        config.debug = true

        PostHogSDK.shared.setup(config)
//        PostHogSDK.shared.capture("Event from MacOS example!")
    }

    func applicationWillTerminate(_: Notification) {
        // Insert code here to tear down your application
    }
}
