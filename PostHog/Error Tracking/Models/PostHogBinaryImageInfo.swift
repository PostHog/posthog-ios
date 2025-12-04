//
//  PostHogBinaryImageInfo.swift
//  PostHog
//
//  Created by Ioannis Josephides on 27/11/2025.
//

import Foundation

/// Information about a loaded binary image (executable or dynamic library)
///
/// This struct contains the metadata needed for server-side symbolication:
/// - UUID for matching uploaded dSYM files
/// - Load addresses for calculating symbol offsets
/// - Size for determining address ranges
struct PostHogBinaryImageInfo {
    /// Full path to the binary image (e.g., "/usr/lib/system/libsystem_kernel.dylib")
    let name: String

    /// UUID of the binary image, used for dSYM matching
    /// Format: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
    let uuid: String?

    /// Virtual memory address from the Mach-O headers (preferred load address)
    let vmAddress: UInt64

    /// Actual load address in memory (may differ from vmAddress due to ASLR)
    let address: UInt64

    /// Size of the binary image in bytes
    let size: UInt64

    var toDictionary: [String: Any] {
        var dict: [String: Any] = [
            "type": "macho",
            "code_file": name,
            "image_addr": String(format: "0x%llx", address),
            "image_size": size,
        ]

        if let uuid = uuid {
            dict["debug_id"] = uuid
        }

        if vmAddress > 0 {
            dict["image_vmaddr"] = String(format: "0x%llx", vmAddress)
        }

        return dict
    }
}
