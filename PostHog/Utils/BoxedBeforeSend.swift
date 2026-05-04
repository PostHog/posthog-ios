//
//  BoxedBeforeSend.swift
//  PostHog
//

import Foundation

/// ObjC bridges for the Swift function-typed `beforeSend` chains.
///
/// Swift function types (`(PostHogEvent) -> PostHogEvent?`,
/// `(PostHogMutableLogRecord) -> PostHogMutableLogRecord?`) aren't `@objc`-bridgeable, so
/// ObjC callers pass these boxed wrappers to `setBeforeSend(_:)` instead.
/// Each function shape needs its own concrete `@objc` class — `@objc` classes
/// can't be generic, so the duplication below is the minimum overhead for
/// ObjC interop. Swift callers use the variadic `setBeforeSend(_:)` overloads
/// directly and never see these boxes.

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
