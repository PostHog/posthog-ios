//
//  PostHogHingeStatusTest.swift
//  PostHogTests
//
//  Created by Anna Garcia on 28/09/2026.
//

import Foundation
@testable import PostHog
import Testing
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(UIKit, _version: 9127.0.85)
    import UIKit
#endif

@Suite("Hinge status on events")
struct PostHogHingeStatusTest {
    private func getSut(status: String?) -> PostHogContext {
        #if os(watchOS)
            let sut = PostHogContext()
        #else
            let sut = PostHogContext(nil)
        #endif
        sut.hingeStatusObserver = PostHogHingeStatusObserver()
        sut.hingeStatusObserver.setStatus(status)
        return sut
    }

    @Test("adds $hinge_status while the device reports a hinge status", arguments: ["closed", "partially_open", "fully_open"])
    func reportsStatus(status: String) {
        let sut = getSut(status: status)

        #expect(sut.dynamicContext()["$hinge_status"] as? String == status)
    }

    @Test("leaves $hinge_status out when there is no hinge status")
    func omitsStatusWithoutHinge() {
        let sut = getSut(status: nil)

        #expect(sut.dynamicContext()["$hinge_status"] == nil)
    }

    #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(UIKit, _version: 9127.0.85)
        @available(iOS 27.1, *)
        @Test("maps UIHinge.Status to the property value, and leaves unknown out")
        func mapsHingeStatus() {
            #expect(PostHogHingeStatusObserver.value(for: .closed) == "closed")
            #expect(PostHogHingeStatusObserver.value(for: .partiallyOpen) == "partially_open")
            #expect(PostHogHingeStatusObserver.value(for: .fullyOpen) == "fully_open")
            #expect(PostHogHingeStatusObserver.value(for: .unknown) == nil)
        }
    #endif
}
