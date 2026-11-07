#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    @Suite("Application event publisher")
    struct ApplicationEventPublisherTest {
        private final class Recorder {
            private let lock = NSLock()
            private var storage: [String] = []
            var values: [String] { lock.withLock { storage } }
            func append(_ value: String) {
                lock.withLock { storage.append(value) }
            }
        }

        @Test("will-dispatch subscribers run before UIKit dispatch, application-event subscribers after")
        func dispatchOrder() {
            let sut = ApplicationEventPublisher(exchangeSendEvent: {})
            let recorder = Recorder()
            let willDispatch = sut.onApplicationEventWillDispatch.subscribe { _, _ in recorder.append("willDispatch") }
            let didDispatch = sut.onApplicationEvent.subscribe { _, _ in recorder.append("didDispatch") }
            defer { withExtendedLifetime((willDispatch, didDispatch)) {} }

            sut.publish(UIEvent()) { recorder.append("dispatch") }

            #expect(recorder.values == ["willDispatch", "dispatch", "didDispatch"])
        }

        @Test("sendEvent stays swizzled while either callback has subscribers")
        func swizzledWhileEitherHasSubscribers() {
            let exchanges = Recorder()
            let sut = ApplicationEventPublisher(exchangeSendEvent: { exchanges.append("exchange") })

            var willDispatch: RegistrationToken? = sut.onApplicationEventWillDispatch.subscribe { _, _ in }
            #expect(exchanges.values.count == 1)
            var didDispatch: RegistrationToken? = sut.onApplicationEvent.subscribe { _, _ in }
            #expect(exchanges.values.count == 1)

            willDispatch = nil
            #expect(exchanges.values.count == 1, "still swizzled for the remaining subscriber")
            didDispatch = nil
            #expect(exchanges.values.count == 2, "unswizzled once both callbacks are empty")

            willDispatch = sut.onApplicationEventWillDispatch.subscribe { _, _ in }
            #expect(exchanges.values.count == 3)
            withExtendedLifetime((willDispatch, didDispatch)) {}
        }
    }
#endif
