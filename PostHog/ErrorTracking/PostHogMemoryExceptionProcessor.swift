//
//  PostHogMemoryExceptionProcessor.swift
//  PostHog
//

import Foundation

/// One frame of a MetricKit call stack, reduced to what symbolication needs.
///
/// Kept free of MetricKit types so the conversion to `$exception` properties can be
/// tested on every platform, not only on iOS 27.
struct PostHogDiagnosticFrame {
    let binaryUUID: UUID?
    let binaryName: String?
    let address: UInt64
    let offsetIntoBinaryTextSegment: UInt64?
}

/// Converts a MetricKit memory-exception (out-of-memory) diagnostic into `$exception` properties.
enum PostHogMemoryExceptionProcessor {
    static let exceptionType = "OutOfMemory"
    static let exceptionValue = "The app was terminated by the system for exceeding its memory limit"

    /// - Parameter frames: the attributed thread's frames, innermost (crash site) first.
    static func processFrames(_ frames: [PostHogDiagnosticFrame], config: PostHogErrorTrackingConfig) -> [String: Any] {
        var stackFrames: [PostHogStackFrame] = []
        var imagesByLoadAddress: [UInt64: PostHogBinaryImageInfo] = [:]

        for frame in frames {
            let address = frame.address.pacStripped
            let module = frame.binaryName

            // MetricKit gives no load address, but `address - offset` is exactly that.
            var imageAddress: UInt64?
            if let offset = frame.offsetIntoBinaryTextSegment, offset <= address {
                let loadAddress = address - offset
                imageAddress = loadAddress
                // Symbolication finds the dSYM by UUID, so an image without one is useless.
                if imagesByLoadAddress[loadAddress] == nil, let module, let uuid = frame.binaryUUID {
                    imagesByLoadAddress[loadAddress] = PostHogBinaryImageInfo(
                        name: module,
                        uuid: uuid.uuidString,
                        vmAddress: nil,
                        address: loadAddress,
                        // Not reported by MetricKit; symbolication matches frames by `image_addr`.
                        size: 0
                    )
                }
            }

            stackFrames.append(PostHogStackFrame(
                instructionAddress: address,
                module: module,
                package: module,
                imageAddress: imageAddress,
                inApp: module.map { PostHogStackTraceProcessor.isInApp(module: $0, config: config) } ?? false,
                function: nil,
                symbolAddress: nil
            ))
        }

        var exception: [String: Any] = [
            "type": exceptionType,
            "value": exceptionValue,
            "mechanism": [
                "type": "memory_exception",
                "handled": false,
                "synthetic": false,
            ],
        ]
        if !stackFrames.isEmpty {
            // Outermost first, like the crash reporter.
            exception["stacktrace"] = [
                "frames": stackFrames.reversed().map(\.toDictionary),
                "type": "raw",
            ]
        }

        var properties: [String: Any] = [
            "$exception_level": "fatal",
            "$exception_list": [exception],
        ]
        if !imagesByLoadAddress.isEmpty {
            properties["$debug_images"] = imagesByLoadAddress.values.map(\.toDictionary)
        }
        return properties
    }
}
