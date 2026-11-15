//
//  PostHogStackTraceProcessor.swift
//  PostHog
//
//  Created by Ioannis Josephides on 13/11/2025.
//

import Darwin
import Foundation
import MachO

/// Captures and processes stack traces for error tracking
///
/// This class provides methods to capture stack traces from the current thread
/// and format them consistently for error tracking.
///
enum PostHogStackTraceProcessor {
    // MARK: - Stack Trace Capture

    /// Captures current stack trace using dladdr() for rich metadata
    ///
    /// PostHog SDK frames at the top of the stack are kept but marked as not in-app,
    /// so the first in-app frame is user code.
    static func captureCurrentStackTraceWithMetadata(
        config: PostHogErrorTrackingConfig
    ) -> [PostHogStackFrame] {
        let addresses = Thread.callStackReturnAddresses
        return symbolicateAddresses(addresses, config: config, markTopPostHogFramesNotInApp: true)
    }

    /// Captures the current stack for a handled error, keeping the SDK's own frames but marking them as not in-app
    ///
    /// `callerStack` is what the public `captureException` entry point read, starting at the app's call site.
    /// Its frames have the same return addresses here, so every frame above where it begins is the SDK
    /// reporting the error. Those frames can't be recognized by name: a statically linked SDK shares the
    /// app's binary, and stripped release builds have no symbol names.
    ///
    /// - Parameters:
    ///   - callerStack: Return addresses captured in the public API entry point, starting at the caller
    ///   - config: Error tracking configuration
    static func captureCurrentStackTrace(
        callerStack: [NSNumber],
        config: PostHogErrorTrackingConfig
    ) -> [PostHogStackFrame] {
        let addresses = Thread.callStackReturnAddresses
        guard let callerTop = callerStack.first, let sdkFrameCount = addresses.firstIndex(of: callerTop) else {
            // The stacks don't line up, so fall back to the caller's frames alone
            return symbolicateAddresses(callerStack, config: config, markTopPostHogFramesNotInApp: true)
        }
        return symbolicateAddresses(
            addresses,
            config: config,
            markTopPostHogFramesNotInApp: true,
            sdkFrameCount: sdkFrameCount
        )
    }

    /// Symbolicate an array of return addresses using dladdr()
    ///
    /// - Parameters:
    ///   - addresses: Array of return addresses to symbolicate
    ///   - config: Error tracking configuration
    ///   - markTopPostHogFramesNotInApp: If true, PostHog SDK frames at the top of the stack are marked as not in-app
    ///   - sdkFrameCount: Number of addresses at the top that are known to be SDK frames, marked as not in-app
    static func symbolicateAddresses(
        _ addresses: [NSNumber],
        config: PostHogErrorTrackingConfig,
        markTopPostHogFramesNotInApp: Bool = false,
        sdkFrameCount: Int = 0
    ) -> [PostHogStackFrame] {
        var frames: [PostHogStackFrame] = []
        var markingTopSDKFrames = markTopPostHogFramesNotInApp

        for (index, addressNum) in addresses.enumerated() {
            // Strip PAC bits so the address is a valid instruction pointer on arm64e.
            let address = UInt64(addressNum.uintValue).pacStripped
            var info = Dl_info()

            guard dladdr(UnsafeRawPointer(bitPattern: UInt(address)), &info) != 0 else {
                continue
            }

            var module: String?
            var package: String?
            var imageAddress: UInt64?
            // Default to false: if we cannot determine which binary owns this
            // address (dli_fname is nil), we have no evidence it is user code.
            var inApp = false

            // Binary image info
            if let imageName = info.dli_fname {
                let path = String(cString: imageName)
                let moduleName = (path as NSString).lastPathComponent
                module = moduleName
                package = path
                imageAddress = UInt64(UInt(bitPattern: info.dli_fbase))
                inApp = isInApp(module: moduleName, package: path, config: config)
            }
            // If dladdr succeeded but returned no path (shared-cache framework on
            // simulator or private framework on device), the frame is not user code.
            // inApp stays false — no further action needed.

            // Function/symbol info (raw symbols without demangling)
            var function: String?
            var symbolAddress: UInt64?
            if let symbolName = info.dli_sname {
                function = String(cString: symbolName) // Use raw symbol
                symbolAddress = UInt64(UInt(bitPattern: info.dli_saddr))
            }

            // PostHog frames at the top of the stack are the SDK reporting the error, not user code
            if index < sdkFrameCount {
                inApp = false
            } else if markingTopSDKFrames {
                if isPostHogModule(module) || isCaptureExceptionObjCThunk(function) {
                    inApp = false
                } else {
                    markingTopSDKFrames = false
                }
            }

            let frame = PostHogStackFrame(
                instructionAddress: address,
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
    static func isInApp(module: String, package: String? = nil, config: PostHogErrorTrackingConfig) -> Bool {
        // Priority 1: Check includes (highest priority)
        if config.inAppIncludes.contains(where: { module.hasPrefix($0) }) {
            return true
        }

        // Priority 2: Check excludes
        if config.inAppExcludes.contains(where: { module.hasPrefix($0) }) {
            return false
        }

        // Priority 3: Check known system frameworks (hardcoded name list)
        if isSystemFramework(module) {
            return false
        }

        // Priority 3b: Check system binary path (catches private frameworks not in the name list,
        // e.g. "Gestures" from UIKitCore, "Accessibility", etc.)
        // Handles both device paths (/System/...) and Simulator paths (...RuntimeRoot/System/...)
        if isSystemPath(package) {
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
        // Public Apple frameworks
        "Foundation",
        "UIKit",
        "AppKit",
        "CoreFoundation",
        "CoreGraphics",
        "CoreData",
        "CoreLocation",
        "CoreMotion",
        "CoreServices",
        "CoreText",
        "AVFoundation",
        "Metal",
        "MetalKit",
        "SwiftUI",
        "SwiftUICore",
        "Combine",
        "QuartzCore",
        "Security",
        "SystemConfiguration",
        "CFNetwork",
        "WebKit",
        "GraphicsServices",
        "IOKit",
        // Private UIKit sub-frameworks (dyld shared cache, dli_fname may be nil
        // or contain no recognisable path prefix on some OS versions)
        "Gestures",
        "UIKitCore",
        "UIKitMacHelper",
        "Accessibility",
        "AccessibilityUtilities",
        "UpdateCycle",
        "TextInput",
        "UIFoundation",
        "BackBoardServices",
        "FrontBoardServices",
        "SpringBoardServices",
        "RunningBoardServices",
        // System dylibs
        "libsystem_kernel.dylib",
        "libsystem_pthread.dylib",
        "libsystem_c.dylib",
        "libsystem_malloc.dylib",
        "libdispatch.dylib",
        "libswift",
        "libobjc",
        "dyld",
    ]

    /// Check if a module is a known system framework
    private static func isSystemFramework(_ module: String) -> Bool {
        systemPrefixes.contains { module.hasPrefix($0) }
    }

    /// Check if a binary path is a system library path.
    /// Matches both device paths and Simulator runtime paths.
    private static func isSystemPath(_ path: String?) -> Bool {
        guard let path = path else { return false }
        // Device: /System/Library/..., /usr/lib/...
        // Simulator: .../RuntimeRoot/System/Library/..., .../RuntimeRoot/usr/lib/...
        return path.hasPrefix("/System/") ||
            path.hasPrefix("/usr/lib/") ||
            path.contains("/System/Library/") ||
            path.contains("/usr/lib/")
    }

    // MARK: - PostHog Frame Detection

    /// Check if a module belongs to the PostHog SDK
    private static func isPostHogModule(_ module: String?) -> Bool {
        guard let module = module else { return false }
        return module == "PostHog" || module.hasPrefix("PostHog.")
    }

    /// Check if a symbol is the Objective-C thunk of a `PostHogSDK.captureException` overload
    ///
    /// The thunk sits between an Objective-C caller and the Swift method that reads the stack, so it's
    /// left above the caller. Thunk symbols are local, so this only matches in unstripped binaries, where
    /// they're named accurately. Stripping removes them, so this never matches an app frame, but in a
    /// stripped binary that statically links the SDK the thunk frame stays in-app.
    private static func isCaptureExceptionObjCThunk(_ function: String?) -> Bool {
        guard let function = function else { return false }
        return function.hasPrefix("$s7PostHog0aB3SDKC16captureException") && function.hasSuffix("FTo")
    }
}
