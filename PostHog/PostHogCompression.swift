import Foundation

/// How the SDK compresses request bodies before sending them to the PostHog API.
@objc(PostHogCompression) public enum PostHogCompression: Int {
    /// Gzip request bodies. If gzipping fails on device, the body is sent uncompressed.
    case gzip
    /// Send request bodies uncompressed, with no `Content-Encoding` header.
    case none
}
