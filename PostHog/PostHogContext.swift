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
    @ReadWriteLock
    private var screenSize: CGSize?

    #if !os(watchOS)
        private let reachability: Reachability?
    #endif

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

        // iOS app running in compatibility mode (Designed for iPad/iPhone)
        var isiOSAppOnMac = false
        #if os(iOS)
            if #available(iOS 14.0, *) {
                isiOSAppOnMac = ProcessInfo.processInfo.isiOSAppOnMac
            }
        #endif

        // iPad app running on Mac Catalyst
        #if targetEnvironment(macCatalyst)
            let isMacCatalystApp = true
        #else
            let isMacCatalystApp = false
        #endif

        properties["$is_ios_running_on_mac"] = isiOSAppOnMac
        properties["$is_mac_catalyst_app"] = isMacCatalystApp

        #if os(iOS) || os(tvOS)
            let device = UIDevice.current
            // use https://github.com/devicekit/DeviceKit
            let processInfo = ProcessInfo.processInfo

            if isMacCatalystApp || isiOSAppOnMac {
                let underlyingOS = device.systemName
                let underlyingOSVersion = device.systemVersion
                let macOSVersion = processInfo.operatingSystemVersionString

                if isMacCatalystApp {
                    let osVersion = ProcessInfo.processInfo.operatingSystemVersion
                    properties["$os_version"] = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
                } else {
                    let osVersionString = processInfo.operatingSystemVersionString
                    if let versionRange = osVersionString.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) {
                        properties["$os_version"] = osVersionString[versionRange]
                    } else {
                        // fallback to full version string in case formatting changes
                        properties["$os_version"] = osVersionString
                    }
                }
                // device.userInterfaceIdiom reports .pad here, so we use a static value instead
                // - For an app deployable on iPad, the idiom type is always .pad (instead of .mac)
                //
                // Source: https://developer.apple.com/documentation/apple-silicon/adapting-ios-code-to-run-in-the-macos-environment#Handle-unknown-device-types-gracefully
                properties["$os_name"] = "macOS"
                properties["$device_type"] = "Desktop"
                properties["$device_name"] = processInfo.hostName
            } else {
                // use https://github.com/devicekit/DeviceKit
                properties["$os_name"] = device.systemName
                properties["$os_version"] = device.systemVersion
                properties["$device_name"] = device.model

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
            }
        #elseif os(macOS)
            let deviceName = Host.current().localizedName
            if (deviceName?.isEmpty) != nil {
                properties["$device_name"] = deviceName
            }
            let processInfo = ProcessInfo.processInfo
            properties["$os_name"] = "macOS"
            let osVersion = processInfo.operatingSystemVersion
            properties["$os_version"] = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
            properties["$device_type"] = "Desktop"
        #endif

        return properties
    }()

    #if !os(watchOS)
        init(_ reachability: Reachability?) {
            self.reachability = reachability
            registerNotifications()
        }
    #else
        init() {
            if #available(watchOS 7.0, *) {
                registerNotifications()
            } else {
                onShouldUpdateScreenSize()
            }
        }
    #endif

    deinit {
        #if !os(watchOS)
            unregisterNotifications()
        #else
            if #available(watchOS 7.0, *) {
                unregisterNotifications()
            }
        #endif
    }

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
        var sysctlName = "hw.machine"

        // In case of mac catalyst or iOS running on mac:
        // - "hw.machine" returns underlying iPad/iPhone model
        // - "hw.model" returns mac model
        #if targetEnvironment(macCatalyst)
            sysctlName = "hw.model"
        #elseif os(iOS)
            if #available(iOS 14.0, *) {
                if ProcessInfo.processInfo.isiOSAppOnMac {
                    sysctlName = "hw.model"
                }
            }
        #endif

        var size = 0
        sysctlbyname(sysctlName, nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname(sysctlName, &machine, &size, nil, 0)
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

    private func registerNotifications() {
        #if os(iOS) || os(tvOS)
            #if os(iOS)
                NotificationCenter.default.addObserver(self,
                                                       selector: #selector(onOrientationDidChange),
                                                       name: UIDevice.orientationDidChangeNotification,
                                                       object: nil)
            #endif
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(onShouldUpdateScreenSize),
                                                   name: UIWindow.didBecomeKeyNotification,
                                                   object: nil)
        #elseif os(macOS)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(onShouldUpdateScreenSize),
                                                   name: NSWindow.didBecomeKeyNotification,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(onShouldUpdateScreenSize),
                                                   name: NSWindow.didChangeScreenNotification,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(onShouldUpdateScreenSize),
                                                   name: NSApplication.didBecomeActiveNotification,
                                                   object: nil)
        #elseif os(watchOS)
            if #available(watchOS 7.0, *) {
                NotificationCenter.default.addObserver(self,
                                                       selector: #selector(onShouldUpdateScreenSize),
                                                       name: WKApplication.didBecomeActiveNotification,
                                                       object: nil)
            }
        #endif
    }

    private func unregisterNotifications() {
        #if os(iOS) || os(tvOS)
            #if os(iOS)
                NotificationCenter.default.removeObserver(self,
                                                          name: UIDevice.orientationDidChangeNotification,
                                                          object: nil)
            #endif
            NotificationCenter.default.removeObserver(self,
                                                      name: UIWindow.didBecomeKeyNotification,
                                                      object: nil)

        #elseif os(macOS)
            NotificationCenter.default.removeObserver(self,
                                                      name: NSWindow.didBecomeKeyNotification,
                                                      object: nil)
            NotificationCenter.default.removeObserver(self,
                                                      name: NSWindow.didChangeScreenNotification,
                                                      object: nil)
            NotificationCenter.default.removeObserver(self,
                                                      name: NSApplication.didBecomeActiveNotification,
                                                      object: nil)
        #elseif os(watchOS)
            if #available(watchOS 7.0, *) {
                NotificationCenter.default.removeObserver(self,
                                                          name: WKApplication.didBecomeActiveNotification,
                                                          object: nil)
            }
        #endif
    }

    /// Retrieves the current screen size of the application window based on platform
    private func getScreenSize() -> CGSize? {
        #if os(iOS) || os(tvOS)
            return UIApplication.getCurrentWindow(filterForegrounded: false)?.bounds.size
        #elseif os(macOS)
            // NSScreen.frame represents the full screen rectangle and includes any space occupied by menu, dock or camera bezel
            return NSApplication.shared.windows.first { $0.isKeyWindow }?.screen?.frame.size
        #elseif os(watchOS)
            return WKInterfaceDevice.current().screenBounds.size
        #else
            return nil
        #endif
    }

    #if os(iOS)
        // Special treatment for `orientationDidChangeNotification` since the notification seems to be _sometimes_ called early, before screen bounds are flipped
        @objc private func onOrientationDidChange() {
            updateScreenSize {
                self.getScreenSize().map { size in
                    // manually set width and height based on device orientation. (Needed for fast orientation changes)
                    if UIDevice.current.orientation.isLandscape {
                        CGSize(width: max(size.width, size.height), height: min(size.height, size.width))
                    } else {
                        CGSize(width: min(size.width, size.height), height: max(size.height, size.width))
                    }
                }
            }
        }
    #endif

    @objc private func onShouldUpdateScreenSize() {
        updateScreenSize(getScreenSize)
    }

    private func updateScreenSize(_ getSize: @escaping () -> CGSize?) {
        let block = {
            self.screenSize = getSize()
        }
        // ensure block is executed on `main` since closure accesses non thread-safe UI objects like UIApplication
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}
