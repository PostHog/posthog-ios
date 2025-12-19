//
//  PostHogErrorTrackingUtils.swift
//  PostHog
//
//  Created by Ioannis Josephides on 16/12/2025.
//

import Foundation

// MARK: - UUID Formatting

extension String {
    /// Formats a UUID string to the standard hyphenated format
    /// Input can be with or without hyphens, output is always: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
    var formattedAsUUID: String {
        let clean = replacingOccurrences(of: "-", with: "").uppercased()
        guard clean.count == 32 else { return self }

        let idx = clean.startIndex
        let p1 = clean[idx ..< clean.index(idx, offsetBy: 8)]
        let p2 = clean[clean.index(idx, offsetBy: 8) ..< clean.index(idx, offsetBy: 12)]
        let p3 = clean[clean.index(idx, offsetBy: 12) ..< clean.index(idx, offsetBy: 16)]
        let p4 = clean[clean.index(idx, offsetBy: 16) ..< clean.index(idx, offsetBy: 20)]
        let p5 = clean[clean.index(idx, offsetBy: 20) ..< clean.index(idx, offsetBy: 32)]

        return "\(p1)-\(p2)-\(p3)-\(p4)-\(p5)"
    }
}

// MARK: - CPU Architecture Helpers

enum PostHogCPUArchitecture {
    /// Convert CPU type and subtype to architecture string
    /// 
    /// - Parameters:
    ///   - cpuType: Mach-O CPU type
    ///   - cpuSubtype: Mach-O CPU subtype
    /// - Returns: Architecture string (e.g., "arm64", "x86_64") or nil if unknown
    static func archName(cpuType: UInt64, cpuSubtype: UInt64) -> String? {
        // CPU_TYPE_ARM64 = 0x0100000C (16777228)
        // CPU_TYPE_X86_64 = 0x01000007 (16777223)
        // CPU_TYPE_ARM = 12

        switch cpuType {
        case 0x0100_000C: // CPU_TYPE_ARM64
            return "arm64"
        case 0x0100_0007: // CPU_TYPE_X86_64
            return "x86_64"
        case 12: // CPU_TYPE_ARM
            switch cpuSubtype {
            case 9: return "armv7"
            case 11: return "armv7s"
            default: return "arm"
            }
        default:
            return nil
        }
    }
}

// MARK: - Debug Utilities

enum PostHogDebugUtils {
    /// Check if the current process is being traced by a debugger.
    /// Based on https://gist.github.com/dermotos/fde82d3eb617f5085b22893166519d51
    static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard junk == 0 else {
            hedgeLog("Failed to check for debugger. sysctl failed with error code: \(junk)")
            return false
        }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
