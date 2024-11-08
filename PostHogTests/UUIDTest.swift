//
//  UUIDTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 17.06.24.
//

import Foundation

import Foundation
import Nimble
@testable import PostHog
import Quick

class UUIDTest: QuickSpec {
    private func compareULongs(_ l1: UInt64, _ l2: UInt64) -> Int {
        let high1 = Int32(bitPattern: UInt32((l1 >> 32) & 0xFFFF_FFFF))
        let high2 = Int32(bitPattern: UInt32((l2 >> 32) & 0xFFFF_FFFF))
        var diff = compareUInts(high1, high2)
        if diff == 0 {
            let low1 = Int32(bitPattern: UInt32(l1 & 0xFFFF_FFFF))
            let low2 = Int32(bitPattern: UInt32(l2 & 0xFFFF_FFFF))
            diff = compareUInts(low1, low2)
        }
        return diff
    }

    private func compareUInts(_ i1: Int32, _ i2: Int32) -> Int {
        if i1 < 0 {
            return Int(i2 < 0 ? (i1 - i2) : 1)
        }
        return Int(i2 < 0 ? -1 : (i1 - i2))
    }

    override func spec() {
        it("mostSignificantBits") {
            let uuid = UUID(uuidString: "019025e6-b135-7e40-97df-ae0cebef184c")!
            expect(uuid.mostSignificantBits) == 112_631_663_430_041_152
        }

        it("leastSignificantBits") {
            let uuid = UUID(uuidString: "019025e6-b135-7e40-97df-ae0cebef184c")!
            expect(uuid.leastSignificantBits) == -7_503_087_083_654_801_332
        }

        it("test sorted and duplicated") {
            let count = 10000

            var created: [UUID] = []
            for _ in 0 ..< count {
                created.append(UUID.v7())
            }

            let sortedUUIDs = created.sorted { uuid1, uuid2 in
                if uuid1.mostSignificantBits != uuid2.mostSignificantBits {
                    return uuid1.mostSignificantBits < uuid2.mostSignificantBits
                }
                return uuid1.leastSignificantBits < uuid2.leastSignificantBits
            }

            var unique: Set<UUID> = Set(minimumCapacity: count)

            for i in 0 ..< created.count {
                expect(sortedUUIDs[i]) == created[i]
                if !unique.insert(created[i]).inserted {
                    fatalError("Duplicate at index \(i)")
                }
            }
        }
    }
}

extension UUID {
    var mostSignificantBits: Int64 {
        let uuidBytes = withUnsafePointer(to: uuid) {
            $0.withMemoryRebound(to: UInt8.self, capacity: 16) {
                Array(UnsafeBufferPointer(start: $0, count: 16))
            }
        }

        var mostSignificantBits: UInt64 = 0
        for i in 0 ..< 8 {
            mostSignificantBits = (mostSignificantBits << 8) | UInt64(uuidBytes[i])
        }
        return Int64(bitPattern: mostSignificantBits)
    }

    var leastSignificantBits: Int64 {
        let uuidBytes = withUnsafePointer(to: uuid) {
            $0.withMemoryRebound(to: UInt8.self, capacity: 16) {
                Array(UnsafeBufferPointer(start: $0, count: 16))
            }
        }

        var leastSignificantBits: UInt64 = 0
        for i in 8 ..< 16 {
            leastSignificantBits = (leastSignificantBits << 8) | UInt64(uuidBytes[i])
        }
        return Int64(bitPattern: leastSignificantBits)
    }
}
