//
//  PostHogStackTrace.swift
//  PostHog
//
//  Created by Ioannis Josephides on 13/11/2025.
//

import Darwin
import Foundation
import MachO

/// Utility for capturing and processing stack traces
///
/// This class provides methods to capture stack traces from the current thread
/// and format them consistently for error tracking.
///
enum PostHogStackTrace {
    // MARK: - Stack Trace Capture

    /// Captures current stack trace using dladdr() for rich metadata
    ///
    /// Automatically strips PostHog SDK frames from the top of the stack trace
    /// so the trace starts at user code.
    static func captureCurrentStackTraceWithMetadata(
        config: PostHogErrorTrackingConfig
    ) -> [PostHogStackFrame] {
        let addresses = Thread.callStackReturnAddresses
        return symbolicateAddresses(addresses, config: config, stripTopPostHogFrames: true)
    }

    /// Symbolicate an array of return addresses using dladdr()
    ///
    /// - Parameters:
    ///   - addresses: Array of return addresses to symbolicate
    ///   - config: Error tracking configuration
    ///   - stripTopPostHogFrames: If true, strips PostHog SDK frames from the top of the stack
    static func symbolicateAddresses(
        _ addresses: [NSNumber],
        config: PostHogErrorTrackingConfig,
        stripTopPostHogFrames: Bool = false
    ) -> [PostHogStackFrame] {
        var frames: [PostHogStackFrame] = []
        var shouldCollectFrame = !stripTopPostHogFrames

        for addressNum in addresses {
            let address = addressNum.uintValue
            var info = Dl_info()

            guard dladdr(UnsafeRawPointer(bitPattern: UInt(address)), &info) != 0 else {
                continue
            }

            var module: String?
            var package: String?
            var imageAddress: UInt64?
            var inApp = false

            // Binary image info
            if let imageName = info.dli_fname {
                let path = String(cString: imageName)
                let moduleName = (path as NSString).lastPathComponent
                module = moduleName
                package = path
                imageAddress = UInt64(UInt(bitPattern: info.dli_fbase))
                inApp = isInApp(module: moduleName, config: config)
            }

            // Skip PostHog frames at the top of the stack
            if !shouldCollectFrame {
                if isPostHogModule(module) {
                    continue
                }
                shouldCollectFrame = true
            }

            // Function/symbol info (raw symbols without demangling)
            var function: String?
            var symbolAddress: UInt64?
            if let symbolName = info.dli_sname {
                function = String(cString: symbolName) // Use raw symbol
                symbolAddress = UInt64(UInt(bitPattern: info.dli_saddr))
            }

            let frame = PostHogStackFrame(
                instructionAddress: UInt64(address),
                module: module,
                package: package,
                imageAddress: imageAddress,
                inApp: inApp,
                function: function,
                symbolAddress: symbolAddress
            )

            frames.append(frame)
        }

        return frames
    }

    // MARK: - In-App Detection

    /// Determines if a frame is considered in-app
    ///
    /// Priority system (matches posthog-flutter's _isInAppFrame):
    /// 1. inAppIncludes (highest priority)
    /// 2. inAppExcludes
    /// 3. Known system frameworks (hardcoded)
    /// 4. inAppByDefault (final fallback)
    ///
    /// Note: Uses prefix matching, unlike Flutter which uses exact package matching.
    /// This matches Android's behavior for consistency.
    ///
    /// - Parameters:
    ///   - module: The module/binary name to check
    ///   - config: Error tracking configuration
    /// - Returns: true if the frame should be marked as in-app
    static func isInApp(module: String, config: PostHogErrorTrackingConfig) -> Bool {
        // Priority 1: Check includes (highest priority)
        if config.inAppIncludes.contains(where: { module.hasPrefix($0) }) {
            return true
        }

        // Priority 2: Check excludes
        if config.inAppExcludes.contains(where: { module.hasPrefix($0) }) {
            return false
        }

        // Priority 3: Check known system frameworks (hardcoded)
        if isSystemFramework(module) {
            return false
        }

        // Priority 4: Use default (final fallback)
        return config.inAppByDefault
    }

    /// Known system framework prefixes
    ///
    /// Note: This list is based on common system frameworks and dylibs on iOS.
    /// It may need to be updated based on real-world usage, or moved to cymbal
    /// which can further categorize frames and override in-app frames based on module paths
    private static let systemPrefixes = [
        "Foundation",
        "UIKit",
        "CoreFoundation",
        "libsystem_kernel.dylib",
        "libsystem_pthread.dylib",
        "libdispatch.dylib",
        "CoreGraphics",
        "QuartzCore",
        "Security",
        "SystemConfiguration",
        "CFNetwork",
        "CoreData",
        "CoreLocation",
        "AVFoundation",
        "Metal",
        "MetalKit",
        "SwiftUI",
        "Combine",
        "AppKit",
        "libswift",
        "IOKit",
        "WebKit",
        "GraphicsServices",
    ]

    /// Check if a module is a known system framework
    private static func isSystemFramework(_ module: String) -> Bool {
        systemPrefixes.contains { module.hasPrefix($0) }
    }

    // MARK: - PostHog Frame Detection

    /// Check if a module belongs to the PostHog SDK
    private static func isPostHogModule(_ module: String?) -> Bool {
        guard let module = module else { return false }
        return module == "PostHog" || module.hasPrefix("PostHog.")
    }
}
