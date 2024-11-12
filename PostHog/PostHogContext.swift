//
//  PostHogContext.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 16.10.23.
//

import Foundation

#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#elseif os(watchOS)
    import WatchKit
#endif

class PostHogContext {
    #if !os(watchOS)
        private let reachability: Reachability?
    #endif

    private var screenSize: CGSize? {
        let getWindowSize: () -> CGSize? = {
            #if os(iOS) || os(tvOS)
                return UIApplication.getCurrentWindow(filterForegrounded: false)?.bounds.size
            #elseif os(macOS)
                return NSScreen.main?.visibleFrame.size
            #elseif os(watchOS)
                return WKInterfaceDevice.current().screenBounds.size
            #else
                return nil
            #endif
        }

        return Thread.isMainThread
            ? getWindowSize()
            : DispatchQueue.main.sync { getWindowSize() }
    }

    private lazy var theStaticContext: [String: Any] = {
        // Properties that do not change over the lifecycle of an application
        var properties: [String: Any] = [:]

        let infoDictionary = Bundle.main.infoDictionary

        if let appName = infoDictionary?[kCFBundleNameKey as String] {
            properties["$app_name"] = appName
        } else if let appName = infoDictionary?["CFBundleDisplayName"] {
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
        properties["$device_manufacturer"] = "Apple"
        properties["$device_model"] = platform()

        #if targetEnvironment(simulator)
            properties["$is_emulator"] = true
        #else
            properties["$is_emulator"] = false
        #endif

        #if os(iOS) || os(tvOS)
            let device = UIDevice.current
            // use https://github.com/devicekit/DeviceKit
            properties["$device_name"] = device.model
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
        #elseif os(macOS)
            let deviceName = Host.current().localizedName
            if (deviceName?.isEmpty) != nil {
                properties["$device_name"] = deviceName
            }
            let processInfo = ProcessInfo.processInfo
            properties["$os_name"] = "macOS \(processInfo.operatingSystemVersionString)" // eg Version 14.2.1 (Build 23C71)
            let osVersion = processInfo.operatingSystemVersion
            properties["$os_version"] = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
            properties["$device_type"] = "Desktop"
        #endif

        return properties
    }()

    #if !os(watchOS)
        init(_ reachability: Reachability?) {
            self.reachability = reachability
        }
    #else
        init() {}
    #endif

    private lazy var theSdkInfo: [String: Any] = {
        var sdkInfo: [String: Any] = [:]
        sdkInfo["$lib"] = postHogSdkName
        sdkInfo["$lib_version"] = postHogVersion
        return sdkInfo
    }()

    func staticContext() -> [String: Any] {
        theStaticContext
    }

    func sdkInfo() -> [String: Any] {
        theSdkInfo
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

        if let screenSize {
            properties["$screen_width"] = Float(screenSize.width)
            properties["$screen_height"] = Float(screenSize.height)
        }

        if Locale.current.languageCode != nil {
            properties["$locale"] = Locale.current.languageCode
        }
        properties["$timezone"] = TimeZone.current.identifier

        #if !os(watchOS)
            if reachability != nil {
                properties["$network_wifi"] = reachability?.connection == .wifi
                properties["$network_cellular"] = reachability?.connection == .cellular
            }
        #endif

        return properties
    }
}
