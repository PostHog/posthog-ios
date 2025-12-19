//
//  PostHogCrashReportProcessor.swift
//  PostHog
//
//  Created by Ioannis Josephides on 14/12/2025.
//

import Foundation

#if os(iOS) || os(macOS) || os(tvOS)
    import CrashReporter

    enum PostHogCrashReportProcessor {
        /// Process a PLCrashReport and convert it to PostHog $exception event properties
        ///
        /// - Parameter report: The PLCrashReport to process
        /// - Returns: Dictionary of exception-specific properties for the $exception event
        static func processReport(_ report: PLCrashReport) -> [String: Any] {
            var properties: [String: Any] = [:]

            // Fatal crash
            properties["$exception_level"] = "fatal"

            // Build exception list
            var exceptions: [[String: Any]] = []

            if let exceptionInfo = buildExceptionInfo(from: report) {
                exceptions.append(exceptionInfo)
            }

            if !exceptions.isEmpty {
                properties["$exception_list"] = exceptions
            }

            // Build debug images for symbolication
            let debugImages = buildDebugImages(from: report)
            if !debugImages.isEmpty {
                properties["$debug_images"] = debugImages
            }

            // Add crash metadata
            if let uuidRef = report.uuidRef {
                properties["$crash_report_id"] = CFUUIDCreateString(nil, uuidRef) as String
            }
            if let timestamp = report.systemInfo?.timestamp {
                properties["$app_crashed_at"] = toISO8601String(timestamp)
            }

            return properties
        }

        /// Get the crash timestamp from the report
        static func getCrashTimestamp(_ report: PLCrashReport) -> Date? {
            report.systemInfo?.timestamp
        }

        // MARK: - Exception Building

        private static func buildExceptionInfo(from report: PLCrashReport) -> [String: Any]? {
            var exception: [String: Any] = [:]

            // Determine exception type and value based on crash type
            if let machException = report.machExceptionInfo {
                // Mach exception
                exception["type"] = machExceptionName(machException.type)
                exception["value"] = machExceptionMessage(machException)

                exception["mechanism"] = [
                    "type": "mach_exception",
                    "handled": false,
                    "synthetic": false,
                    "meta": [
                        "mach": [
                            "exception": machException.type,
                            "code": machException.codes.first ?? 0,
                            "subcode": machException.codes.count > 1 ? machException.codes[1] : 0,
                        ],
                    ],
                ]
            } else if let signalInfo = report.signalInfo {
                // POSIX signal
                exception["type"] = signalInfo.name ?? "Unknown Signal"
                exception["value"] = signalMessage(signalInfo)

                exception["mechanism"] = [
                    "type": "signal",
                    "handled": false,
                    "synthetic": false,
                    "meta": [
                        "signal": [
                            "code": signalInfo.code ?? "Unknown",
                            "name": signalInfo.name ?? "Unknown",
                        ],
                    ],
                ]
            } else if report.hasExceptionInfo, let nsExceptionInfo = report.exceptionInfo {
                // NSException
                exception["type"] = nsExceptionInfo.exceptionName ?? "NSException"
                exception["value"] = nsExceptionInfo.exceptionReason ?? "Unknown reason"

                exception["mechanism"] = [
                    "type": "nsexception",
                    "handled": false,
                    "synthetic": false,
                ]
            } else {
                return nil
            }

            // Add stack trace from crashed thread
            if let stacktrace = buildStacktrace(from: report) {
                exception["stacktrace"] = stacktrace
            }

            // Add thread ID of crashed thread
            if let crashedThread = findCrashedThread(in: report) {
                exception["thread_id"] = crashedThread.threadNumber
            }

            return exception
        }

        // MARK: - Stack Trace Building

        private static func buildStacktrace(from report: PLCrashReport) -> [String: Any]? {
            guard let crashedThread = findCrashedThread(in: report) else {
                return nil
            }

            var frames: [PostHogStackFrame] = []

            for case let frame as PLCrashReportStackFrameInfo in crashedThread.stackFrames {
                var module: String?
                var package: String?
                var imageAddress: UInt64?
                var function: String?
                var symbolAddress: UInt64?

                // Try to find the binary image for this frame
                if let image = report.image(forAddress: frame.instructionPointer) {
                    imageAddress = image.imageBaseAddress

                    if let imageName = image.imageName {
                        package = (imageName as NSString).lastPathComponent
                        module = package
                    }
                }

                // Add symbol info if available
                if let symbolInfo = frame.symbolInfo {
                    function = symbolInfo.symbolName
                    symbolAddress = symbolInfo.startAddress
                }

                let stackFrame = PostHogStackFrame(
                    instructionAddress: frame.instructionPointer,
                    module: module,
                    package: package,
                    imageAddress: imageAddress,
                    inApp: false, // Cannot determine in-app status from crash report
                    function: function,
                    symbolAddress: symbolAddress
                )
                frames.append(stackFrame)
            }

            guard !frames.isEmpty else { return nil }

            let frameDicts = frames.map(\.toDictionary)

            return [
                "frames": frameDicts,
                "type": "raw",
            ]
        }

        private static func findCrashedThread(in report: PLCrashReport) -> PLCrashReportThreadInfo? {
            for case let thread as PLCrashReportThreadInfo in report.threads where thread.crashed {
                return thread
            }
            // Fallback to first thread if none marked as crashed
            return report.threads.first as? PLCrashReportThreadInfo
        }

        // MARK: - Debug Images

        private static func buildDebugImages(from report: PLCrashReport) -> [[String: Any]] {
            var debugImages: [PostHogBinaryImageInfo] = []

            for case let image as PLCrashReportBinaryImageInfo in report.images {
                guard let imageName = image.imageName else { continue }

                let arch: String?
                if let codeType = image.codeType {
                    arch = PostHogCPUArchitecture.archName(cpuType: codeType.type, cpuSubtype: codeType.subtype)
                } else {
                    arch = nil
                }

                let binaryImage = PostHogBinaryImageInfo(
                    name: imageName,
                    uuid: image.imageUUID?.formattedAsUUID,
                    vmAddress: nil, // PLCrashReport doesn't expose vmAddress
                    address: image.imageBaseAddress,
                    size: image.imageSize,
                    arch: arch
                )
                debugImages.append(binaryImage)
            }

            return debugImages.map(\.toDictionary)
        }

        // MARK: - Helpers

        private static let machExceptionNames: [UInt64: String] = [
            1: "EXC_BAD_ACCESS",
            2: "EXC_BAD_INSTRUCTION",
            3: "EXC_ARITHMETIC",
            4: "EXC_EMULATION",
            5: "EXC_SOFTWARE",
            6: "EXC_BREAKPOINT",
            7: "EXC_SYSCALL",
            8: "EXC_MACH_SYSCALL",
            9: "EXC_RPC_ALERT",
            10: "EXC_CRASH",
            11: "EXC_RESOURCE",
            12: "EXC_GUARD",
            13: "EXC_CORPSE_NOTIFY",
        ]

        private static func machExceptionName(_ type: UInt64) -> String {
            machExceptionNames[type] ?? "EXC_UNKNOWN(\(type))"
        }

        private static func machExceptionMessage(_ exception: PLCrashReportMachExceptionInfo) -> String {
            let typeName = machExceptionName(exception.type)
            let codesArray = exception.codes as? [NSNumber]
            let codes = codesArray?.map { String(describing: $0) }.joined(separator: ", ") ?? ""
            return "\(typeName) at codes: [\(codes)]"
        }

        private static func signalMessage(_ signal: PLCrashReportSignalInfo) -> String {
            let name = signal.name ?? "Unknown"
            let code = signal.code ?? "Unknown"
            let address = String(format: PostHogStackFrame.hexAddressFormat, signal.address)

            return "\(name) (code \(code)) at address \(address)"
        }
    }
#endif
