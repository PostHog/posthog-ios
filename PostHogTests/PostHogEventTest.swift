import Foundation
@testable import PostHog
import Testing

@Suite("PostHogEvent JSON decoding")
struct PostHogEventTest {
    @Test("ignores the 2.x top-level $set and message_id")
    func ignoresV2Fields() throws {
        let messageId = "5CE069F8-E967-4B47-9D89-207EF7519453"
        let json: [String: Any] = [
            "event": "test",
            "distinct_id": "user",
            "properties": ["key": "value"],
            "$set": ["plan": "pro"],
            "message_id": messageId,
        ]

        let event = try #require(PostHogEvent.fromJSON(json))

        #expect(event.properties["$set"] == nil)
        #expect(event.properties["key"] as? String == "value")
        #expect(event.uuid.uuidString != messageId)
    }

    @Test("reads uuid")
    func readsUuid() throws {
        let uuid = "019A0000-0000-7000-8000-000000000001"
        let json: [String: Any] = [
            "event": "test",
            "distinct_id": "user",
            "uuid": uuid,
        ]

        let event = try #require(PostHogEvent.fromJSON(json))

        #expect(event.uuid.uuidString == uuid)
    }
}
