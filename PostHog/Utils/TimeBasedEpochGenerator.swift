//
//  TimeBasedEpochGenerator.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 17.06.24.
//

import Foundation

class TimeBasedEpochGenerator {
    static let shared = TimeBasedEpochGenerator()

    // Private initializer to prevent multiple instances
    private init() {}

    private var lastEntropy = [UInt8](repeating: 0, count: 10)
    private var lastTimestamp: UInt64 = 0

    private let lock = NSLock()

    func v7() -> UUID {
        var uuid: UUID?

        lock.withLock {
            uuid = generateUUID()
        }

        // or fallback to UUID v4
        return uuid ?? UUID()
    }

    private func generateUUID() -> UUID? {
        let timestamp = Date().timeIntervalSince1970
        let unixTimeMilliseconds = UInt64(timestamp * 1000)

        var uuidBytes = [UInt8]()

        let timeBytes = unixTimeMilliseconds.bigEndianData.suffix(6) // First 6 bytes for the timestamp
        uuidBytes.append(contentsOf: timeBytes)

        if unixTimeMilliseconds == lastTimestamp {
            var check = true
            for index in (0 ..< 10).reversed() where check {
                var temp = lastEntropy[index]
                temp = temp &+ 0x01
                check = lastEntropy[index] == 0xFF
                lastEntropy[index] = temp
            }
        } else {
            lastTimestamp = unixTimeMilliseconds

            // Prepare the random part (10 bytes to complete the UUID)
            let status = SecRandomCopyBytes(kSecRandomDefault, lastEntropy.count, &lastEntropy)
            // If we can't generate secure random bytes, use a fallback
            if status != errSecSuccess {
                let randomData = (0 ..< 10).map { _ in UInt8.random(in: 0 ... 255) }
                lastEntropy = randomData
            }
        }
        uuidBytes.append(contentsOf: lastEntropy)

        // Set version (7) in the version byte
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x70

        // Set the UUID variant (10xx for standard UUIDs)
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80

        // Ensure we have a total of 16 bytes
        if uuidBytes.count == 16 {
            return UUID(uuid: (uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
                               uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
                               uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
                               uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]))
        }

        return nil
    }
}

extension UInt64 {
    // Correctly generate Data representation in big endian format
    var bigEndianData: Data {
        var bigEndianValue = bigEndian
        return Data(bytes: &bigEndianValue, count: MemoryLayout<UInt64>.size)
    }
}
