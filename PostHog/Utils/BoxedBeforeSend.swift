//
//  BoxedBeforeSend.swift
//  PostHog
//

import Foundation

/// ObjC wrappers for the Swift function-typed `beforeSend` chains: Swift
/// function types aren't `@objc`-bridgeable, and `@objc` classes can't be
/// generic, so each function shape gets its own concrete box. Swift callers
/// use the variadic `setBeforeSend(_:)` overloads and never see these.

/// ObjC wrapper for the events `beforeSend` block. Use with
/// `PostHogConfig.setBeforeSend(_:)`.
@objc public final class BoxedBeforeSendBlock: NSObject {
    @objc public let block: BeforeSendBlock

    @objc(block:)
    public init(block: @escaping BeforeSendBlock) {
        self.block = block
    }
}

/// ObjC wrapper for the logs `beforeSend` block. Use with
/// `PostHogLogsConfig.setBeforeSend(_:)`.
@objc public final class BoxedBeforeSendLogBlock: NSObject {
    @objc public let block: PostHogBeforeSendLogBlock

    @objc(block:)
    public init(block: @escaping PostHogBeforeSendLogBlock) {
        self.block = block
    }
}
