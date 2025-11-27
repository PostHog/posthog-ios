//
//  PostHogStackTrace.swift
//  PostHog
//
//  Created by Ioannis Josephides on 13/11/2025.
//

import Darwin
import Foundation
import MachO

/// Represents a single stack trace frame
///
struct PostHogStackFrame {
    /// Instruction address (e.g., "0x0000000104e5c123")
    /// This is the actual program counter address where the frame is executing
    let instructionAddr: String?

    /// Symbol address - start address of the function (for calculating offset)
    /// Used to compute: instructionOffset = instructionAddr - symbolAddr
    let symbolAddr: String?

    /// Image (binary) base address where the module is loaded in memory
    let imageAddr: String?

    /// UUID of the binary image (for server-side symbolication with dSYM files)
    let imageUUID: String?

    /// Module/binary name (e.g., "MyApp", "Foundation", "UIKit")
    let module: String?

    /// Function/method name (e.g., "myMethod()", "-[NSException raise]")
    let function: String?

    /// Source file name (e.g., "MyClass.swift")
    let filename: String?

    /// Line number in source file
    let lineno: Int?

    /// Column number in source file (optional)
    let colno: Int?

    /// Platform identifier ("swift", "objc")
    let platform: String

    /// Whether this frame is in-app code (set by in-app detection)
    var inApp: Bool

    /// Convert to dictionary format for JSON serialization
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "platform": platform,
            "in_app": inApp,
        ]

        if let instructionAddr = instructionAddr {
            dict["instruction_addr"] = instructionAddr
        }

        if let symbolAddr = symbolAddr {
            dict["symbol_addr"] = symbolAddr
        }

        if let imageAddr = imageAddr {
            dict["image_addr"] = imageAddr
        }

        if let imageUUID = imageUUID {
            dict["image_uuid"] = imageUUID
        }

        if let module = module {
            dict["module"] = module
        }

        if let function = function {
            dict["function"] = function
        }

        if let filename = filename {
            dict["filename"] = filename
        }

        if let lineno = lineno {
            dict["lineno"] = lineno
        }

        if let colno = colno {
            dict["colno"] = colno
        }

        return dict
    }
}


/// Utility for extracting and parsing stack traces
///
/// This class provides methods to extract stack traces from various sources
/// (NSException, Swift Error, raw strings) and format them consistently
/// for error tracking.
///
class PostHogStackTrace {
    // MARK: - Current Thread Stack Trace (Primary Method)

    /// Capture stack trace from current thread using raw addresses
    ///
    /// This is the primary method for capturing stack traces for Swift Errors.
    /// Uses Thread.callStackReturnAddresses to get raw instruction addresses,
    /// then symbolicates them using dladdr().
    ///
    /// Reference: Sentry iOS uses this approach for manual error capture
    ///
    /// - Parameter skipFrames: Number of frames to skip from the top (default 2 to skip capture methods)
    /// - Returns: Array of stack frames with symbolication information
    static func captureCurrentThreadStackTrace(skipFrames: Int = 2) -> [PostHogStackFrame] {
        // Get raw return addresses from the call stack
        let addresses = Thread.callStackReturnAddresses

        guard addresses.count > skipFrames else {
            return []
        }

        // Skip the top frames (this method and its callers)
        let relevantAddresses = addresses.dropFirst(skipFrames)

        // Symbolicate each address using dladdr()
        return relevantAddresses.map { addressNumber in
            symbolicateAddress(addressNumber)
        }
    }

    // MARK: - Address Symbolication using dladdr()

    /// Symbolicate a single address using dladdr()
    ///
    /// This performs on-device symbolication to extract symbol information
    /// from a raw instruction address. The symbolication may be limited for
    /// stripped binaries, but raw addresses are preserved for server-side
    /// symbolication.
    ///
    static func symbolicateAddress(_ addressNumber: NSNumber) -> PostHogStackFrame {
        let address = addressNumber.uintValue
        let pointer = UnsafeRawPointer(bitPattern: address)

        var info = Dl_info()
        var instructionAddr: String?
        var symbolAddr: String?
        var imageAddr: String?
        var module: String?
        var function: String?

        // Store the raw instruction address (always available)
        instructionAddr = String(format: "0x%016lx", address)

        // Use dladdr() to get symbol information
        if let ptr = pointer, dladdr(ptr, &info) != 0 {
            // Extract image (binary) base address
            if let dlifbase = info.dli_fbase {
                imageAddr = String(format: "0x%016lx", UInt(bitPattern: dlifbase))
            }

            // Extract module/binary name
            if let dlifname = info.dli_fname {
                let path = String(cString: dlifname)
                module = (path as NSString).lastPathComponent
            }

            // Extract symbol address and name
            if let dlisaddr = info.dli_saddr {
                symbolAddr = String(format: "0x%016lx", UInt(bitPattern: dlisaddr))
            }

            if let dlisname = info.dli_sname {
                let symbolName = String(cString: dlisname)
                function = demangle(symbolName)

                // Detect platform based on symbol naming
//                if symbolName.hasPrefix("_$s") || symbolName.hasPrefix("$s") || symbolName.contains("Swift") {
//                    platform = "swift"
//                } else if symbolName.hasPrefix("-[") || symbolName.hasPrefix("+[") {
//                    platform = "objc"
//                }
            }
        }

        return PostHogStackFrame(
            instructionAddr: instructionAddr,
            symbolAddr: symbolAddr,
            imageAddr: imageAddr,
            imageUUID: nil, // Will be populated by matching with binary images
            module: module,
            function: function,
            filename: nil, // Not available from dladdr()
            lineno: nil, // Not available from dladdr()
            colno: nil,
            platform: "ios",
            inApp: false // Will be set by in-app detection later
        )
    }

    /// Attempt to demangle a symbol name
    ///
    /// Swift symbols are usually mangled (e.g., "_$s4MyApp0A5ClassC6methodyyF").
    /// This attempts basic demangling for readability.
    private static func demangle(_ symbolName: String) -> String {
        // For now, return the mangled name as-is
        // TODO: Could use _stdlib_demangleName or swift-demangle for full demangling
        symbolName
    }


    // MARK: - NSException Stack Trace Extraction (Fallback)

    /// Extract stack trace from NSException
    ///
    /// NSException provides callStackSymbols (formatted strings) which we parse.
    /// This is a fallback method since NSException doesn't expose raw addresses easily.
    ///
    static func extractStackTrace(from exception: NSException) -> [PostHogStackFrame] {
        let symbols = exception.callStackSymbols
        guard !symbols.isEmpty else {
            return []
        }

        return symbols.enumerated().map { index, symbol in
            parseStackSymbol(symbol, frameIndex: index)
        }
    }

    // MARK: - String Parsing (Fallback)

    /// Parse a multi-line stack trace string
    ///
    /// Useful for parsing crash logs or pre-formatted stack traces.
    ///
    /// - Parameter stackTrace: Multi-line string containing stack trace
    static func parseStackTraceString(_ stackTrace: String) -> [PostHogStackFrame] {
        let lines = stackTrace.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return lines.enumerated().map { index, line in
            parseStackSymbol(line, frameIndex: index)
        }
    }

    // MARK: - Symbol Parsing (Fallback for formatted strings)

    /// Parse a single stack trace symbol string
    ///
    /// Parses various formats:
    /// - "0   MyApp   0x00000001045a8f40 MyApp + 12345"
    /// - "2   Foundation   0x00007fff2e4f6a9c -[NSException raise] + 123"
    /// - "4   MyApp   0x0000000104e5c123 MyClass.myMethod() -> () (MyFile.swift:42)"
    ///
    /// This is kept as a fallback for NSException.callStackSymbols
    private static func parseStackSymbol(_ symbol: String, frameIndex _: Int) -> PostHogStackFrame {
        var instructionAddr: String?
        var module: String?
        var function: String?
        var filename: String?
        var lineno: Int?

        // Extract address using regex
        if let addressMatch = symbol.range(of: "0x[0-9a-fA-F]+", options: .regularExpression) {
            instructionAddr = String(symbol[addressMatch])
        }

        // Split by whitespace to extract components
        let components = symbol.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // Typical format: "frameNumber  moduleName  address  function  +  offset"
        if components.count >= 2 {
            module = components[1]
        }

        // Extract function name (everything after address, before +offset)
        if let addrMatch = symbol.range(of: "0x[0-9a-fA-F]+", options: .regularExpression),
           let plusMatch = symbol.range(of: " \\+ \\d+", options: .regularExpression)
        {
            let functionStart = symbol.index(after: addrMatch.upperBound)
            let functionEnd = plusMatch.lowerBound

            if functionStart < functionEnd {
                let functionPart = symbol[functionStart ..< functionEnd].trimmingCharacters(in: .whitespaces)
                if !functionPart.isEmpty {
                    function = functionPart
                }
            }
        } else if let addrMatch = symbol.range(of: "0x[0-9a-fA-F]+", options: .regularExpression) {
            // No +offset, take everything after address
            let functionStart = symbol.index(after: addrMatch.upperBound)
            let functionPart = symbol[functionStart...].trimmingCharacters(in: .whitespaces)
            if !functionPart.isEmpty {
                function = functionPart
            }
        }

        // Extract Swift file and line number: (FileName.swift:lineNumber)
        if let fileMatch = symbol.range(of: "\\([^)]+\\.swift:\\d+\\)", options: .regularExpression) {
            let fileInfo = String(symbol[fileMatch])
            // Remove parentheses
            let cleaned = fileInfo.trimmingCharacters(in: CharacterSet(charactersIn: "()"))

            // Split by colon
            let parts = cleaned.components(separatedBy: ":")
            if parts.count == 2 {
                filename = parts[0]
                lineno = Int(parts[1])
            }
        }

        return PostHogStackFrame(
            instructionAddr: instructionAddr,
            symbolAddr: nil,
            imageAddr: nil,
            imageUUID: nil,
            module: module,
            function: function,
            filename: filename,
            lineno: lineno,
            colno: nil,
            platform: "ios",
            inApp: false // Will be set by in-app detection later
        )
    }

    // MARK: - Comprehensive Stack Trace Capture (Primary Implementation)

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
            if let symbolName = info.dli_sname {
                frame["function"] = String(cString: symbolName)
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
        "GraphicsServices"
    ]

    /// Check if a module is a known system framework
    private static func isSystemFramework(_ module: String) -> Bool {
        return systemPrefixes.contains { module.hasPrefix($0) }
    }
}
