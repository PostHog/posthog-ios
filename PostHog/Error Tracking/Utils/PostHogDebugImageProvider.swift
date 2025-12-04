//
//  PostHogDebugImageProvider.swift
//  PostHog
//
//  Created by Ioannis Josephides on 28/11/2025.
//

import Foundation
import MachO

/// Utility for extracting debug image metadata from loaded binary images
///
/// This provider extracts information needed for server-side symbolication:
/// - UUID from LC_UUID load command (for dSYM matching)
/// - Text segment address and size (for address range calculation)
/// - Load addresses (for offset calculation)
///
enum PostHogDebugImageProvider {
    private static let segmentText = "__TEXT"

    /// Get all currently loaded binary images with their metadata
    ///
    /// Uses dyld APIs to enumerate all loaded images and parse their Mach-O headers.
    ///
    /// NOTE:
    /// This will do for now, but we should eventually use dyld callbacks to track
    /// image loading/unloading and cache images via
    /// `_dyld_register_func_for_add_image` / `_dyld_register_func_for_remove_image`
    /// for quicker lookups (this is what Sentry is doing as well).
    ///
    /// - Returns: Array of binary image info for all loaded images
    static func getAllBinaryImages() -> [PostHogBinaryImageInfo] {
        var images: [PostHogBinaryImageInfo] = []

        let imageCount = _dyld_image_count()

        for index in 0 ..< imageCount {
            guard let header = _dyld_get_image_header(index) else { continue }
            let slide = _dyld_get_image_vmaddr_slide(index)
            let name = _dyld_get_image_name(index).map { String(cString: $0) } ?? "unknown"

            if let imageInfo = parseImageInfo(header: header, slide: slide, name: name) {
                images.append(imageInfo)
            }
        }

        return images
    }

    /// Get debug images for stack frames
    ///
    /// Extracts unique image addresses from frames and returns their binary metadata.
    ///
    /// - Parameter frames: Array of stack frame dictionaries containing "image_addr" keys
    /// - Returns: Array of debug image dictionaries
    static func getDebugImages(for frames: [[String: Any]]) -> [[String: Any]] {
        let addresses = Set(frames.compactMap { $0["image_addr"] as? String })
        guard !addresses.isEmpty else { return [] }
        return getImages(for: addresses).map(\.toDictionary)
    }

    /// Get debug images for exception list
    ///
    /// Extracts frames from all exceptions and returns their binary metadata.
    ///
    /// - Parameter exceptions: Array of exception dictionaries (from $exception_list)
    /// - Returns: Array of debug image dictionaries
    static func getDebugImages(fromExceptions exceptions: [[String: Any]]) -> [[String: Any]] {
        let frames = exceptions.flatMap { exception -> [[String: Any]] in
            guard let stacktrace = exception["stacktrace"] as? [String: Any],
                  let frames = stacktrace["frames"] as? [[String: Any]] else { return [] }
            return frames
        }
        return getDebugImages(for: frames)
    }

    // MARK: - Internal

    /// Get binary images for a set of image addresses
    private static func getImages(for imageAddresses: Set<String>) -> [PostHogBinaryImageInfo] {
        guard !imageAddresses.isEmpty else { return [] }

        // Convert hex strings to UInt64 for comparison
        let addressValues = Set(imageAddresses.compactMap { hexToUInt64($0) })
        guard !addressValues.isEmpty else { return [] }

        var matchedImages: [PostHogBinaryImageInfo] = []
        let imageCount = _dyld_image_count()

        for index in 0 ..< imageCount {
            guard let header = _dyld_get_image_header(index) else { continue }
            let slide = _dyld_get_image_vmaddr_slide(index)
            let name = _dyld_get_image_name(index).map { String(cString: $0) } ?? "unknown"

            if let imageInfo = parseImageInfo(header: header, slide: slide, name: name),
               addressValues.contains(imageInfo.address)
            {
                matchedImages.append(imageInfo)
            }
        }

        return matchedImages
    }

    /// Parse binary image info from a Mach-O header
    ///
    /// Supports both 32-bit and 64-bit Mach-O formats by detecting the magic number
    /// and using the appropriate header size and segment command type.
    private static func parseImageInfo(
        header: UnsafePointer<mach_header>,
        slide: Int,
        name: String
    ) -> PostHogBinaryImageInfo? {
        let is64Bit = header.pointee.magic == MH_MAGIC_64 || header.pointee.magic == MH_CIGAM_64

        // Configuration based on architecture
        let headerSize = is64Bit ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size
        let segmentCmd = is64Bit ? UInt32(LC_SEGMENT_64) : UInt32(LC_SEGMENT)

        var uuid: String?
        var textVMAddr: UInt64 = 0
        var textSize: UInt64 = 0

        // Start of load commands (right after header)
        var cmdPtr = UnsafeRawPointer(header).advanced(by: headerSize)
        let ncmds = header.pointee.ncmds

        for _ in 0 ..< ncmds {
            let cmd = cmdPtr.assumingMemoryBound(to: load_command.self).pointee

            switch cmd.cmd {
            case UInt32(LC_UUID):
                uuid = extractUUID(from: cmdPtr)

            case segmentCmd:
                let segment = extractTextSegment(from: cmdPtr, is64Bit: is64Bit)
                if let segment = segment {
                    textVMAddr = segment.vmaddr
                    textSize = segment.vmsize
                }

            default:
                break
            }

            // Early exit once we have both UUID and __TEXT segment
            if uuid != nil, textSize > 0 {
                break
            }

            cmdPtr = cmdPtr.advanced(by: Int(cmd.cmdsize))
        }

        // Calculate actual load address (vmaddr + slide)
        let loadAddress = UInt64(Int64(textVMAddr) + Int64(slide))

        return PostHogBinaryImageInfo(
            name: name,
            uuid: uuid,
            vmAddress: textVMAddr,
            address: loadAddress,
            size: textSize
        )
    }

    /// Extract __TEXT segment info from a segment command
    ///
    /// - Parameters:
    ///   - cmdPtr: Pointer to the segment command
    ///   - is64Bit: Whether this is a 64-bit segment command
    /// - Returns: Tuple of (vmaddr, vmsize) if this is the __TEXT segment, nil otherwise
    private static func extractTextSegment(
        from cmdPtr: UnsafeRawPointer,
        is64Bit: Bool
    ) -> (vmaddr: UInt64, vmsize: UInt64)? {
        if is64Bit {
            let segCmd = cmdPtr.assumingMemoryBound(to: segment_command_64.self).pointee
            let segName = withUnsafeBytes(of: segCmd.segname) { ptr -> String? in
                let bytes = ptr.bindMemory(to: CChar.self)
                guard let baseAddress = bytes.baseAddress else { return nil }
                return String(cString: baseAddress)
            }
            guard segName == segmentText else { return nil }
            return (segCmd.vmaddr, segCmd.vmsize)
        } else {
            let segCmd = cmdPtr.assumingMemoryBound(to: segment_command.self).pointee
            let segName = withUnsafeBytes(of: segCmd.segname) { ptr -> String? in
                let bytes = ptr.bindMemory(to: CChar.self)
                guard let baseAddress = bytes.baseAddress else { return nil }
                return String(cString: baseAddress)
            }
            guard segName == segmentText else { return nil }
            return (UInt64(segCmd.vmaddr), UInt64(segCmd.vmsize))
        }
    }

    /// Extract UUID from LC_UUID load command
    ///
    /// The UUID is stored as 16 bytes in the uuid_command structure.
    /// We format it as a standard UUID string with hyphens.
    private static func extractUUID(from cmdPtr: UnsafeRawPointer) -> String? {
        let uuidCmd = cmdPtr.assumingMemoryBound(to: uuid_command.self).pointee
        let uuid = uuidCmd.uuid

        // Format as UUID string: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
        return String(
            format: "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            uuid.0, uuid.1, uuid.2, uuid.3,
            uuid.4, uuid.5,
            uuid.6, uuid.7,
            uuid.8, uuid.9,
            uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15
        )
    }

    // MARK: - Helpers

    /// Convert hex string (e.g., "0x100abc000") to UInt64
    private static func hexToUInt64(_ hex: String) -> UInt64? {
        var hexString = hex
        if hexString.hasPrefix("0x") || hexString.hasPrefix("0X") {
            hexString = String(hexString.dropFirst(2))
        }
        return UInt64(hexString, radix: 16)
    }
}
