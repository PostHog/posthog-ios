import Foundation
import Nimble
import Quick

@testable import PostHog

class PostHogTest: QuickSpec {
    func getSut() -> PostHogSDK {
        let config = PostHogConfig(apiKey: "123", host: "http://localhost:9001")
        return PostHogSDK.with(config)
    }

    override func spec() {
        var server: MockPostHogServer!

        beforeEach {
            server = MockPostHogServer()
            server.start()
        }
        afterEach {
            server.stop()
        }

        it("setups default IDs") {
            let sut = self.getSut()

            expect(sut.getAnonymousId()).toNot(beNil())
            expect(sut.getDistinctId()) == sut.getAnonymousId()

            sut.reset()
        }

        it("setups optOut") {
            let sut = self.getSut()

            sut.optOut()

            expect(sut.isOptOut()) == true

            sut.optIn()

            expect(sut.isOptOut()) == false

            sut.reset()
        }

        it("calls reloadFeatureFlags") {
            let sut = self.getSut()

            let group = DispatchGroup()
            group.enter()

            sut.reloadFeatureFlags {
                group.leave()
            }

            group.wait()

            expect(sut.isFeatureEnabled("bool-value")) == true

            sut.reset()
        }

        it("identify sets distinct and anon Ids") {
            let sut = self.getSut()

            let distId = sut.getDistinctId()

            sut.identify("newDistinctId")

            expect(sut.getDistinctId()) == "newDistinctId"
            expect(sut.getAnonymousId()) == distId

            sut.reset()
        }
    }
}
