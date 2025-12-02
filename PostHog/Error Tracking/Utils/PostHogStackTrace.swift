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
    static func captureCurrentStackTraceWithMetadata(
        config: PostHogErrorTrackingConfig,
        skipFrames: Int = 3
    ) -> [PostHogStackFrame] {
        let addresses = Thread.callStackReturnAddresses
        return symbolicateAddresses(addresses, config: config, skipFrames: skipFrames)
    }

    /// Symbolicate an array of return addresses using dladdr()
    static func symbolicateAddresses(
        _ addresses: [NSNumber],
        config: PostHogErrorTrackingConfig,
        skipFrames: Int
    ) -> [PostHogStackFrame] {
        var frames: [PostHogStackFrame] = []

        for (index, addressNum) in addresses.enumerated() {
            guard index >= skipFrames else { continue }

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
                module = (path as NSString).lastPathComponent
                package = path
                imageAddress = UInt64(UInt(bitPattern: info.dli_fbase))
                inApp = isInApp(module: module!, config: config)
            }

            // Function/symbol info
            var function: String?
            var symbolAddress: UInt64?
            if let symbolName = info.dli_sname {
                let rawSymbol = String(cString: symbolName)
                function = demangle(rawSymbol)
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
}
