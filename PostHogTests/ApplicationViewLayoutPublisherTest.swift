//
//  ApplicationViewLayoutPublisherTest.swift
//  PostHog
//
//  Created by Ioannis Josephides on 26/03/2025.
//

#if os(iOS)
    import Foundation
    import Testing

    @testable import PostHog

    @Suite("Application View Publisher Test", .serialized)
    final class ApplicationViewLayoutPublisherTest {
        var registrationToken: RegistrationToken?

        @MainActor
        @Test("throttles layout views correctly")
        func throttleLayoutViews() async throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            var timesCalled = 0
            var lastCallTime: Date?

            let sut = ApplicationViewLayoutPublisher.shared
            registrationToken = sut.onViewLayout(throttle: 2) {
                timesCalled += 1
                lastCallTime = mockNow.date
            }

            // First call should trigger immediately
            sut.simulateLayoutSubviews()

            let firstCallDate = mockNow.date
            #expect(timesCalled == 1)
            #expect(lastCallTime == firstCallDate)

            // These calls should be throttled (all within 2s)
            mockNow.date.addTimeInterval(0.6)
            sut.simulateLayoutSubviews()
            mockNow.date.addTimeInterval(0.6)
            sut.simulateLayoutSubviews()
            mockNow.date.addTimeInterval(0.6)
            sut.simulateLayoutSubviews()

            #expect(timesCalled == 1, "Calls within throttle interval should be ignored")
            #expect(lastCallTime == firstCallDate)

            // This call should trigger (>2s since last trigger)
            mockNow.date.addTimeInterval(0.4) // Total: 2.2s
            sut.simulateLayoutSubviews()

            #expect(timesCalled == 2)
            #expect(lastCallTime == mockNow.date)

            registrationToken = nil
        }
    }
#endif
