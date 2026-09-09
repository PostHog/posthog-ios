import Foundation
@testable import PostHog
import Testing

struct StoredSurveyResponseTest {
    @Test("stored response values survive JSON encoding and decoding", arguments: [
        PostHogSurveyResponse.rating(nil), .rating(5), .openEnded("hello"), .openEnded(nil),
        .singleChoice("A"), .multipleChoice(["A", "B"]), .multipleChoice(nil), .link(true), .link(false),
    ])
    func storedResponseRoundTrip(response: PostHogSurveyResponse) throws {
        let restored = try #require(JSONDecoder().decode(StoredSurveyResponse.self, from: JSONEncoder().encode(StoredSurveyResponse(response))).response)
        #expect(restored.type == response.type)
        #expect(restored.textValue == response.textValue)
        #expect(restored.ratingValue == response.ratingValue)
        #expect(restored.selectedOptions == response.selectedOptions)
        #expect(restored.linkClicked == response.linkClicked)
    }
}
