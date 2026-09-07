import Foundation
import Vapor

/// Translate the harness's ISO-8601 input to the SDK's existing Date argument.
func parseCaptureTimestamp(_ input: String?) throws -> Date? {
    guard let input else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: input) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: input) else {
        throw Abort(.badRequest, reason: "Invalid ISO-8601 timestamp")
    }
    return date
}
