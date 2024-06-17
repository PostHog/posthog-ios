//
//  UUIDUtils.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 17.06.24.
//

// Inspired and adapted from https://github.com/nthState/UUIDV7/blob/main/Sources/UUIDV7/UUIDV7.swift
// but using SecRandomCopyBytes

import Foundation

public extension UUID {
    static func v7() -> Self {
        let timestamp = Date().timeIntervalSince1970
        let unixTimeMilliseconds = UInt64(timestamp * 1000)
        let timeBytes = unixTimeMilliseconds.bigEndianData.suffix(6) // First 6 bytes for the timestamp

        // Prepare the random part (10 bytes to complete the UUID)
        var randomBytes = [UInt8](repeating: 0, count: 10)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        // If we can't generate secure random bytes, use a fallback
        if status != errSecSuccess {
            let randomData = (0 ..< 10).map { _ in UInt8.random(in: 0 ... 255) }
            randomBytes = randomData
        }

        // Combine parts
        var uuidBytes = [UInt8]()
        uuidBytes.append(contentsOf: timeBytes)
        uuidBytes.append(contentsOf: randomBytes)

        // Set version (7) in the version byte
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x70

        // Set the UUID variant (10xx for standard UUIDs)
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80

        // Ensure we have a total of 16 bytes
        if uuidBytes.count == 16 {
            let uuid = UUID(uuid: (uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
                                   uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
                                   uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
                                   uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]))
            return uuid
        } else {
            // or fallback to UUID v4
            return UUID()
        }
    }
}

extension UInt64 {
    // Correctly generate Data representation in big endian format
    var bigEndianData: Data {
        var bigEndianValue = bigEndian
        return Data(bytes: &bigEndianValue, count: MemoryLayout<UInt64>.size)
    }
}
