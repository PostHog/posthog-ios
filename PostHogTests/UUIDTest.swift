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

@available(iOS 17, *)
class UUIDTest: QuickSpec {
    override func spec() {
        it("test duplicated") {
            let count = 10000

            var created: [UUID] = []
            for _ in 0 ..< count {
                created.append(UUID.v7())
            }

            var unique: Set<UUID> = Set(minimumCapacity: count)

            for i in 0 ..< created.count {
                if !unique.insert(created[i]).inserted {
                    fatalError("Duplicate at index \(i)")
                }
            }
        }
    }
}
