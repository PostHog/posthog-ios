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
    // MARK: - Swift Symbol Demangling

    /// Type alias for the swift_demangle function signature
    private typealias SwiftDemangleFunc = @convention(c) (
        _ mangledName: UnsafePointer<UInt8>?,
        _ mangledNameLength: Int,
        _ outputBuffer: UnsafeMutablePointer<UInt8>?,
        _ outputBufferSize: UnsafeMutablePointer<Int>?,
        _ flags: UInt32
    ) -> UnsafeMutablePointer<Int8>?

    /// Cached reference to the swift_demangle function
    private static let swiftDemangleFunc: SwiftDemangleFunc? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let sym = dlsym(handle, "swift_demangle")
        else {
            return nil
        }
        return unsafeBitCast(sym, to: SwiftDemangleFunc.self)
    }()

    /// Attempt to demangle a Swift symbol name
    ///
    /// Swift symbols are mangled (e.g., "_$s4MyApp0A5ClassC6methodyyF").
    /// This uses the Swift runtime's swift_demangle function to convert
    /// them to human-readable form (e.g., "MyApp.MyClass.method() -> ()").
    ///
    /// - Parameter symbolName: The mangled symbol name
    /// - Returns: The demangled name if successful, otherwise the original name
    private static func demangle(_ symbolName: String) -> String {
        // Only attempt to demangle Swift symbols
        // Swift mangled names start with "$s", "_$s", "$S", or "_$S"
        guard symbolName.hasPrefix("$s") ||
            symbolName.hasPrefix("_$s") ||
            symbolName.hasPrefix("$S") ||
            symbolName.hasPrefix("_$S")
        else {
            return symbolName
        }

        guard let demangleFunc = swiftDemangleFunc else {
            return symbolName
        }

        // Call swift_demangle - must use withCString to get proper pointer
        let demangled = symbolName.withCString { cString -> String? in
            // swift_demangle expects UnsafePointer<UInt8>, convert from Int8
            let result = cString.withMemoryRebound(to: UInt8.self, capacity: symbolName.utf8.count) { ptr in
                demangleFunc(ptr, symbolName.utf8.count, nil, nil, 0)
            }
            guard let demangledCString = result else { return nil }
            defer { demangledCString.deallocate() }
            return String(cString: demangledCString)
        }

        return demangled ?? symbolName
    }

    // MARK: - Stack Trace Capture

    /// Captures current stack trace using dladdr() for rich metadata
    ///
    /// This approach is inspired by Sentry's implementation and provides:
    /// - Instruction addresses (critical for server-side symbolication)
    /// - Binary image addresses and names
    /// - Symbol addresses for function resolution
    /// - Proper in-app detection based on binary images
    ///
    /// - Parameters:
    ///   - config: Error tracking configuration for in-app detection
    ///   - skipFrames: Number of frames to skip from the beginning (default 3)
    /// - Returns: Array of frame dictionaries with metadata
    static func captureCurrentStackTraceWithMetadata(
        config: PostHogErrorTrackingConfig,
        skipFrames: Int = 3
    ) -> [[String: Any]] {
        let addresses = Thread.callStackReturnAddresses
        return symbolicateAddresses(addresses, config: config, skipFrames: skipFrames)
    }

    /// Symbolicate an array of return addresses using dladdr()
    ///
    /// - Parameters:
    ///   - addresses: Array of return addresses as NSNumber
    ///   - config: Error tracking configuration for in-app detection
    ///   - skipFrames: Number of frames to skip from the beginning
    /// - Returns: Array of frame dictionaries with metadata
    static func symbolicateAddresses(
        _ addresses: [NSNumber],
        config: PostHogErrorTrackingConfig,
        skipFrames: Int
    ) -> [[String: Any]] {
        var frames: [[String: Any]] = []

        for (index, addressNum) in addresses.enumerated() {
            guard index >= skipFrames else { continue }

            let address = addressNum.uintValue
            var info = Dl_info()

            guard dladdr(UnsafeRawPointer(bitPattern: UInt(address)), &info) != 0 else {
                continue
            }

            var frame: [String: Any] = [:]

            // Instruction address (hex format for compatibility with PostHog backend)
            frame["instruction_addr"] = String(format: "0x%016llx", address)

            // Binary image info
            if let imageName = info.dli_fname {
                let path = String(cString: imageName)
                let module = (path as NSString).lastPathComponent

                frame["module"] = module
                frame["package"] = path // Full binary path for symbolication
                frame["image_addr"] = String(format: "0x%016llx", UInt(bitPattern: info.dli_fbase))

                // In-app detection based on binary image
                frame["in_app"] = isInApp(module: module, config: config)
            }

            // Function/symbol info
            // NOTE: dladdr() returns the nearest symbol it can find, which may be INCORRECT
            // for stripped binaries. In production App Store builds, symbols are often stripped
            // and dladdr() may return a wrong symbol (like a type metadata accessor) or nothing.
            // Server-side symbolication with dSYMs is required for accurate function names
            // in production crash reports.
            if let symbolName = info.dli_sname {
                let rawSymbol = String(cString: symbolName)
                frame["function"] = demangle(rawSymbol)
                frame["symbol_addr"] = String(format: "0x%016llx", UInt(bitPattern: info.dli_saddr))
            }

            // Platform detection (native for objective-c/swift compiled code)
            frame["platform"] = "ios"

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
}
