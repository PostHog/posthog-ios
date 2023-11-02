//
//  PostHogContext.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 16.10.23.
//

import Foundation

#if os(iOS) || os(tvOS)
    import UIKit
#endif

class PostHogContext {
    private let reachability: Reachability?

    private lazy var theStaticContext: [String: Any] = {
        // Properties that do not change over the lifecycle of an application
        var properties: [String: Any] = [:]

        let infoDictionary = Bundle.main.infoDictionary

        if let appName = infoDictionary?[kCFBundleNameKey as String] {
            properties["$app_name"] = appName
        }
        if let appVersion = infoDictionary?["CFBundleShortVersionString"] {
            properties["$app_version"] = appVersion
        }
        if let appBuild = infoDictionary?["CFBundleVersion"] {
            properties["$app_build"] = appBuild
        }

        if Bundle.main.bundleIdentifier != nil {
            properties["$app_namespace"] = Bundle.main.bundleIdentifier
        }

        #if os(iOS) || os(tvOS)
            let device = UIDevice.current
            // use https://github.com/devicekit/DeviceKit
            properties["$device_model"] = platform()
            properties["$device_name"] = device.model
            properties["$device_manufacturer"] = "Apple"
            properties["$os_name"] = device.systemName
            properties["$os_version"] = device.systemVersion

            var deviceType: String?
            switch device.userInterfaceIdiom {
            case UIUserInterfaceIdiom.phone:
                deviceType = "Mobile"
            case UIUserInterfaceIdiom.pad:
                deviceType = "Tablet"
            case UIUserInterfaceIdiom.tv:
                deviceType = "TV"
            case UIUserInterfaceIdiom.carPlay:
                deviceType = "CarPlay"
            case UIUserInterfaceIdiom.mac:
                deviceType = "Desktop"
            default:
                deviceType = nil
            }
            if deviceType != nil {
                properties["$device_type"] = deviceType
            }
        #endif

        return properties
    }()

    init(_ reachability: Reachability?) {
        self.reachability = reachability
    }

    func staticContext() -> [String: Any] {
        theStaticContext
    }

    private func platform() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    func dynamicContext() -> [String: Any] {
        var properties: [String: Any] = [:]

        #if os(iOS) || os(tvOS)
            properties["$screen_width"] = Float(UIScreen.main.bounds.width)
            properties["$screen_height"] = Float(UIScreen.main.bounds.height)
        #endif

        properties["$lib"] = "posthog-ios"
        properties["$lib_version"] = postHogVersion

        if Locale.current.languageCode != nil {
            properties["$locale"] = Locale.current.languageCode
        }
        properties["$timezone"] = TimeZone.current.identifier

        if reachability != nil {
            properties["$network_wifi"] = reachability?.connection == .wifi
            properties["$network_cellular"] = reachability?.connection == .cellular
        }

        return properties
    }
}
