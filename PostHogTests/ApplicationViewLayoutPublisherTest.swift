//
//  ApplicationViewLayoutPublisherTest.swift
//  PostHog
//
//  Created by Ioannis Josephides on 26/03/2025.
//

#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    private final class StubbedLayoutView: UIView {}

    // Only used off-main while this view's original layout forwarding is replaced by a test stub.
    private struct StubbedLayoutCall: @unchecked Sendable {
        let view: UIView
        let layer: CALayer
    }

    @Suite("Application View Publisher Test", .serialized, .resetsGlobalState)
    final class ApplicationViewLayoutPublisherTest {
        var registrationToken: RegistrationToken?

        @MainActor
        private func withOriginalLayoutStub(
            _ original: @escaping (UIView, CALayer) -> Void,
            perform body: (UIView, CALayer) async throws -> Void
        ) async throws {
            try #require(ApplicationViewLayoutPublisher.shared.onViewLayout.subscriberCount == 0)
            let view = StubbedLayoutView()
            let layer = view.layer
            let method = try #require(class_getInstanceMethod(UIView.self, #selector(UIView.layoutSublayers(of:))))
            let selector = #selector(UIView.ph_swizzled_layoutSublayers(of:))
            let block: @convention(block) (UIView, CALayer) -> Void = original
            let stub = imp_implementationWithBlock(block)
            let implementation = method_getImplementation(method)
            // Replace only this test view's call-through; other UIView instances keep their UIKit layout.
            class_replaceMethod(StubbedLayoutView.self, selector, stub, method_getTypeEncoding(method))
            defer {
                registrationToken = nil
                class_replaceMethod(StubbedLayoutView.self, selector, implementation, method_getTypeEncoding(method))
                imp_removeBlock(stub)
            }
            try await body(view, layer)
            // Drain off-main layout notifications before another test subscribes to the shared publisher.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }

        private func runOffMain(_ body: @escaping () -> Void) throws {
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                body()
                finished.signal()
            }
            try #require(finished.wait(timeout: .now() + 5) == .success)
        }

        private func captureStdout(_ body: () throws -> Void) throws -> String {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            defer { try? FileManager.default.removeItem(at: url) }
            let file = try FileHandle(forWritingTo: url)
            defer { file.closeFile() }
            fflush(stdout)
            let saved = dup(STDOUT_FILENO)
            try #require(saved >= 0)
            defer { close(saved) }
            try #require(dup2(file.fileDescriptor, STDOUT_FILENO) >= 0)
            defer {
                fflush(stdout)
                dup2(saved, STDOUT_FILENO)
            }
            try body()
            fflush(stdout)
            return try String(contentsOf: url, encoding: .utf8)
        }

        @MainActor
        @Test("forwards layout synchronously on the calling thread and notifies on main", arguments: [false, true])
        func forwardsLayout(background: Bool) async throws {
            let wasLogging = hedgeLogEnabled
            hedgeLogEnabled = false
            defer { hedgeLogEnabled = wasLogging }
            var originalCalls: [(UIView, CALayer, Bool)] = []
            var notifications = 0
            try await withOriginalLayoutStub({ view, layer in
                originalCalls.append((view, layer, Thread.isMainThread))
            }) { view, layer in
                registrationToken = ApplicationViewLayoutPublisher.shared.onViewLayout.subscribe(throttle: 0, trailing: true) {
                    #expect(Thread.isMainThread)
                    #expect(originalCalls.count == 1)
                    notifications += 1
                }
                if background {
                    try runOffMain { view.layoutSublayers(of: layer) }
                } else {
                    view.layoutSublayers(of: layer)
                }
                try #require(originalCalls.count == 1)
                #expect(originalCalls[0].0 === view)
                #expect(originalCalls[0].1 === layer)
                #expect(originalCalls[0].2 == !background)
                await waitUntil { notifications == 1 }
                #expect(notifications == 1)
            }
        }

        @MainActor
        @Test("warns before forwarding off-main layout only once while debug logging is enabled", arguments: [1, 32])
        func warnsAboutBackgroundLayout(calls: Int) async throws {
            let wasLogging = hedgeLogEnabled
            defer { hedgeLogEnabled = wasLogging }
            let warning = "UIView.layoutSublayers(of:) was called off the main thread"
            let marker = "original-layout-called"
            try await withOriginalLayoutStub({ _, _ in print(marker) }) { view, layer in
                let publisher = ApplicationViewLayoutPublisher.shared
                publisher.resetBackgroundLayoutWarning()
                defer { publisher.resetBackgroundLayoutWarning() }
                registrationToken = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {}

                hedgeLogEnabled = false
                let disabled = try captureStdout {
                    try runOffMain { view.layoutSublayers(of: layer) }
                }
                #expect(!disabled.contains(warning))
                #expect(disabled.contains(marker))

                hedgeLogEnabled = true
                let main = try captureStdout { view.layoutSublayers(of: layer) }
                #expect(!main.contains(warning))
                #expect(main.contains(marker))

                let call = StubbedLayoutCall(view: view, layer: layer)
                let concurrent = try captureStdout {
                    try runOffMain {
                        DispatchQueue.concurrentPerform(iterations: calls) { _ in
                            call.view.layoutSublayers(of: call.layer)
                        }
                    }
                }
                #expect(concurrent.components(separatedBy: warning).count - 1 == 1)
                #expect(concurrent.components(separatedBy: marker).count - 1 == calls)
                if calls == 1 {
                    let warningRange = try #require(concurrent.range(of: warning))
                    let originalRange = try #require(concurrent.range(of: marker))
                    #expect(warningRange.lowerBound < originalRange.lowerBound)
                }

                registrationToken = nil
                registrationToken = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {}
                let restarted = try captureStdout {
                    try runOffMain { view.layoutSublayers(of: layer) }
                }
                #expect(!restarted.contains(warning))
                #expect(restarted.contains(marker))
            }
        }

        // invoke() hops to a background throttle queue then back to main, so effects are async.
        @MainActor
        private func waitUntil(timeoutNanoseconds: UInt64 = 1_000_000_000,
                               pollNanoseconds: UInt64 = 5_000_000,
                               _ condition: () -> Bool) async
        {
            let start = DispatchTime.now().uptimeNanoseconds
            while !condition(), DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
                try? await Task.sleep(nanoseconds: pollNanoseconds)
            }
        }

        @MainActor
        @Test("throttles layout views correctly")
        func throttleLayoutViews() async throws {
            let mockNow = MockDate()
            now = { mockNow.date }
            defer { now = { Date() } }

            var timesCalled = 0
            var lastCallTime: Date?

            let sut = ApplicationViewLayoutPublisher.shared
            registrationToken = sut.onViewLayout.subscribe(throttle: 2) {
                timesCalled += 1
                lastCallTime = mockNow.date
            }

            sut.simulateLayoutSubviews()
            await waitUntil { timesCalled == 1 }

            let firstCallDate = mockNow.date
            #expect(timesCalled == 1)
            #expect(lastCallTime == firstCallDate)

            // Within the 2s throttle window, so each must be ignored. invokeIfReady reads the
            // mocked clock when its async block runs, so let it settle before advancing the clock.
            for _ in 0 ..< 3 {
                mockNow.date.addTimeInterval(0.6)
                sut.simulateLayoutSubviews()
                try? await Task.sleep(nanoseconds: 20 * NSEC_PER_MSEC)
            }

            #expect(timesCalled == 1, "Calls within throttle interval should be ignored")
            #expect(lastCallTime == firstCallDate)

            // >2s since last trigger, so this one fires.
            mockNow.date.addTimeInterval(0.4) // Total: 2.2s
            sut.simulateLayoutSubviews()
            await waitUntil { timesCalled == 2 }

            #expect(timesCalled == 2)
            #expect(lastCallTime == mockNow.date)

            registrationToken = nil
        }
    }
#endif
