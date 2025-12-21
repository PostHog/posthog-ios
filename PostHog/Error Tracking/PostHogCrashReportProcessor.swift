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
        /// - Parameters:
        ///   - report: The PLCrashReport to process
        ///   - config: Error tracking configuration for in-app detection
        /// - Returns: Dictionary of exception-specific properties for the $exception event
        static func processReport(_ report: PLCrashReport, config: PostHogErrorTrackingConfig) -> [String: Any] {
            var properties: [String: Any] = [:]

            // Fatal crash
            properties["$exception_level"] = "fatal"

            // Build stack frames once, reuse for both exception info and debug images
            let stackFrames = buildStackFrames(from: report, config: config)

            // Build exception list
            var exceptions: [[String: Any]] = []

            if let exceptionInfo = buildExceptionInfo(from: report, stackFrames: stackFrames) {
                exceptions.append(exceptionInfo)
            }

            if !exceptions.isEmpty {
                properties["$exception_list"] = exceptions
            }

            // Build debug images for symbolication (only images referenced in stack trace)
            let debugImages = buildDebugImages(from: report, stackFrames: stackFrames)
            if !debugImages.isEmpty {
                properties["$debug_images"] = debugImages
            }

            // Add crash metadata
            if let uuidRef = report.uuidRef {
                properties["$crash_report_id"] = CFUUIDCreateString(nil, uuidRef) as String
            }
            
            return properties
        }

        /// Get the crash timestamp from the report
        static func getCrashTimestamp(_ report: PLCrashReport) -> Date? {
            report.systemInfo?.timestamp
        }

        // MARK: - Exception Building

        private static func buildExceptionInfo(from report: PLCrashReport, stackFrames: [PostHogStackFrame]) -> [String: Any]? {
            var exception: [String: Any] = [:]

            // Determine exception type and value based on crash type
            // Priority: NSException (richest info) → Signal (more familiar) → Mach (lowest level)
            if report.hasExceptionInfo, let nsExceptionInfo = report.exceptionInfo {
                // NSException - has actual exception name and reason
                exception["type"] = nsExceptionInfo.exceptionName
                exception["value"] = nsExceptionInfo.exceptionReason

                exception["mechanism"] = [
                    "type": "nsexception",
                    "handled": false,
                    "synthetic": false,
                ]
            } else if let signalInfo = report.signalInfo {
                // POSIX signal - more familiar to developers (SIGTRAP, SIGABRT, etc.)
                //
                // Note: Swift crashes (fatalError, preconditionFailure, force unwrap, etc.) appear as SIGTRAP.
                // The actual error message is stored in the __crash_info Mach-O section of libswiftCore.dylib,
                // which PLCrashReporter doesn't expose. Sentry/Bugsnag parse this section to get the message.
                // See: https://github.com/getsentry/sentry-cocoa/pull/1596
                // Future enhancement: implement __crash_info parsing for richer Swift crash messages.
                exception["type"] = signalInfo.name
                exception["value"] = signalMessage(signalInfo)

                let signalMeta: [String: Any?] = [
                    "code": signalInfo.code,
                    "name": signalInfo.name,
                ].compactMapValues { $0 }

                exception["mechanism"] = [
                    "type": "signal",
                    "handled": false,
                    "synthetic": false,
                    "meta": ["signal": signalMeta].compactMapValues { $0 },
                ]
            } else if let machException = report.machExceptionInfo {
                // Mach exception - lowest level, fallback
                exception["type"] = machExceptionName(machException.type)
                exception["value"] = machExceptionMessage(machException)

                exception["mechanism"] = [
                    "type": "mach_exception",
                    "handled": false,
                    "synthetic": false,
                    "meta": [
                        "mach": [
                            "exception": machException.type,
                            "code": machException.codes.first,
                            "subcode": machException.codes.count > 1 ? machException.codes[1] : nil,
                        ].compactMapValues { $0 },
                    ].compactMapValues { $0 },
                ]
            } else {
                return nil
            }

            // Add stack trace from frames
            if !stackFrames.isEmpty {
                exception["stacktrace"] = [
                    "frames": stackFrames.map(\.toDictionary),
                    "type": "raw",
                ]
            }

            // Add thread ID of crashed thread
            // Note: Uses PLCrashReporter's threadNumber (sequential index) rather than Mach thread ID,
            // since the original process has terminated and pthread_mach_thread_np is not available.
            if let crashedThread = findCrashedThread(in: report) {
                exception["thread_id"] = crashedThread.threadNumber
            }

            // cleanup nil values
            exception = exception.compactMapValues { $0 }

            return exception
        }

        // MARK: - Stack Frames

        /// Builds stack frames from the crashed thread.

        private static func buildStackFrames(
            from report: PLCrashReport,
            config: PostHogErrorTrackingConfig
        ) -> [PostHogStackFrame] {
            guard let crashedThread = findCrashedThread(in: report) else {
                return []
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

                // Determine in-app status based on module name and config
                let inApp = module.map { PostHogStackTraceProcessor.isInApp(module: $0, config: config) } ?? false

                let stackFrame = PostHogStackFrame(
                    instructionAddress: frame.instructionPointer,
                    module: module,
                    package: package,
                    imageAddress: imageAddress,
                    inApp: inApp,
                    function: function,
                    symbolAddress: symbolAddress
                )
                frames.append(stackFrame)
            }

            return frames
        }

        private static func findCrashedThread(in report: PLCrashReport) -> PLCrashReportThreadInfo? {
            for case let thread as PLCrashReportThreadInfo in report.threads where thread.crashed {
                return thread
            }
            // Fallback to first thread if none marked as crashed
            return report.threads.first as? PLCrashReportThreadInfo
        }

        // MARK: - Debug Images

        /// Build debug images for symbolication, including only images referenced in the stack frames.
        private static func buildDebugImages(
            from report: PLCrashReport,
            stackFrames: [PostHogStackFrame]
        ) -> [[String: Any]] {
            // Extract unique image addresses from stack frames
            let referencedImageAddresses = Set(stackFrames.compactMap(\.imageAddress))
            guard !referencedImageAddresses.isEmpty else { return [] }

            var debugImages: [PostHogBinaryImageInfo] = []

            for case let image as PLCrashReportBinaryImageInfo in report.images {
                guard referencedImageAddresses.contains(image.imageBaseAddress),
                      let imageName = image.imageName
                else { continue }

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
        
        /// Format string for zero-padded 64-bit hex addresses (e.g., "0x00007fff12345678")
        static let hexAddressPaddedFormat = "0x%016llx"

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

        // Exception codes for EXC_BREAKPOINT (from mach/arm/exception.h)
        private static let breakpointCodeNames: [Int64: String] = [
            1: "EXC_ARM_BREAKPOINT",
        ]

        // Exception codes for EXC_BAD_INSTRUCTION (from mach/arm/exception.h)
        private static let badInstructionCodeNames: [Int64: String] = [
            1: "EXC_ARM_UNDEFINED",
            2: "EXC_ARM_SME_DISALLOWED",
        ]

        // Exception codes for EXC_ARITHMETIC (from mach/arm/exception.h)
        private static let arithmeticCodeNames: [Int64: String] = [
            0: "EXC_ARM_FP_UNDEFINED",
            1: "EXC_ARM_FP_IO",
            2: "EXC_ARM_FP_DZ",
            3: "EXC_ARM_FP_OF",
            4: "EXC_ARM_FP_UF",
            5: "EXC_ARM_FP_IX",
            6: "EXC_ARM_FP_ID",
        ]

        // Kernel return codes (used as first code for EXC_BAD_ACCESS)
        // From mach/kern_return.h
        private static let kernelReturnCodeNames: [Int64: String] = [
            0: "KERN_SUCCESS",
            1: "KERN_INVALID_ADDRESS",
            2: "KERN_PROTECTION_FAILURE",
            3: "KERN_NO_SPACE",
            4: "KERN_INVALID_ARGUMENT",
            5: "KERN_FAILURE",
            6: "KERN_RESOURCE_SHORTAGE",
            7: "KERN_NOT_RECEIVER",
            8: "KERN_NO_ACCESS",
            9: "KERN_MEMORY_FAILURE",
            10: "KERN_MEMORY_ERROR",
            11: "KERN_ALREADY_IN_SET",
            12: "KERN_NOT_IN_SET",
            13: "KERN_NAME_EXISTS",
            14: "KERN_ABORTED",
            15: "KERN_INVALID_NAME",
            16: "KERN_INVALID_TASK",
            17: "KERN_INVALID_RIGHT",
            18: "KERN_INVALID_VALUE",
            19: "KERN_UREFS_OVERFLOW",
            20: "KERN_INVALID_CAPABILITY",
            21: "KERN_RIGHT_EXISTS",
            22: "KERN_INVALID_HOST",
            23: "KERN_MEMORY_PRESENT",
            24: "KERN_MEMORY_DATA_MOVED",
            25: "KERN_MEMORY_RESTART_COPY",
            26: "KERN_INVALID_PROCESSOR_SET",
            27: "KERN_POLICY_LIMIT",
            28: "KERN_INVALID_POLICY",
            29: "KERN_INVALID_OBJECT",
            30: "KERN_ALREADY_WAITING",
            31: "KERN_DEFAULT_SET",
            32: "KERN_EXCEPTION_PROTECTED",
            33: "KERN_INVALID_LEDGER",
            34: "KERN_INVALID_MEMORY_CONTROL",
            35: "KERN_INVALID_SECURITY",
            36: "KERN_NOT_DEPRESSED",
            37: "KERN_TERMINATED",
            38: "KERN_LOCK_SET_DESTROYED",
            39: "KERN_LOCK_UNSTABLE",
            40: "KERN_LOCK_OWNED",
            41: "KERN_LOCK_OWNED_SELF",
            42: "KERN_SEMAPHORE_DESTROYED",
            43: "KERN_RPC_SERVER_TERMINATED",
            44: "KERN_RPC_TERMINATE_ORPHAN",
            45: "KERN_RPC_CONTINUE_ORPHAN",
            46: "KERN_NOT_SUPPORTED",
            47: "KERN_NODE_DOWN",
            48: "KERN_NOT_WAITING",
            49: "KERN_OPERATION_TIMED_OUT",
            50: "KERN_CODESIGN_ERROR",
            // ARM-specific codes for EXC_BAD_ACCESS (from mach/arm/exception.h)
            0x101: "EXC_ARM_DA_ALIGN", // 257
            0x102: "EXC_ARM_DA_DEBUG", // 258
            0x103: "EXC_ARM_SP_ALIGN", // 259
            0x104: "EXC_ARM_SWP", // 260
            0x105: "EXC_ARM_PAC_FAIL", // 261
        ]

        private static func machExceptionMessage(_ exception: PLCrashReportMachExceptionInfo) -> String {
            let typeName = machExceptionName(exception.type)

            guard let codesArray = exception.codes as? [NSNumber], !codesArray.isEmpty else {
                return typeName
            }

            let code = codesArray[0].int64Value
            let subcode = codesArray.count > 1 ? codesArray[1].int64Value : nil

            // Format code with name if available (exception-type-specific)
            let codeStr: String
            switch exception.type {
            case 1: // EXC_BAD_ACCESS
                if let codeName = kernelReturnCodeNames[code] {
                    codeStr = "\(codeName) (\(code))"
                } else {
                    codeStr = String(code)
                }
            case 2: // EXC_BAD_INSTRUCTION
                if let codeName = badInstructionCodeNames[code] {
                    codeStr = "\(codeName) (\(code))"
                } else {
                    codeStr = String(code)
                }
            case 3: // EXC_ARITHMETIC
                if let codeName = arithmeticCodeNames[code] {
                    codeStr = "\(codeName) (\(code))"
                } else {
                    codeStr = String(code)
                }
            case 6: // EXC_BREAKPOINT
                if let codeName = breakpointCodeNames[code] {
                    codeStr = "\(codeName) (\(code))"
                } else {
                    codeStr = String(code)
                }
            default:
                codeStr = String(code)
            }

            // Format subcode as hex address if present
            if let subcode = subcode {
                let subcodeHex = String(format: hexAddressPaddedFormat, UInt64(bitPattern: subcode))
                return "\(typeName), Code \(codeStr), Subcode \(subcodeHex)"
            } else {
                return "\(typeName), Code \(codeStr)"
            }
        }

        private static func signalMessage(_ signal: PLCrashReportSignalInfo) -> String? {
            guard let name = signal.name,  let code = signal.code else {
                return nil
            }

            let address = String(format: PostHogStackFrame.hexAddressFormat, signal.address)
            return "\(name) (code \(code)) at address \(address)"
        }
    }
#endif
