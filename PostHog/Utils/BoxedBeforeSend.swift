//
//  BoxedBeforeSend.swift
//  PostHog
//

import Foundation
internal import PostHogObjCExceptionSupport

/// ObjC wrappers for the Swift function-typed `beforeSend` chains: Swift
/// function types aren't `@objc`-bridgeable, and `@objc` classes can't be
/// generic, so each function shape gets its own concrete box. Swift callers
/// use the variadic `setBeforeSend(_:)` overloads and never see these.

/// ObjC wrapper for the events `beforeSend` block. Use with
/// `PostHogConfig.setBeforeSend(_:)`.
@objc public final class BoxedBeforeSendBlock: NSObject, Sendable {
    /// Wrapped event callback.
    @objc public let block: BeforeSendBlock

    /// Creates a boxed event callback for Objective-C callers.
    ///
    /// - Parameter block: Callback that can mutate or drop an event.
    @objc(block:)
    public init(block: @escaping BeforeSendBlock) {
        self.block = block
    }

    func invokeSafely(with event: PostHogEvent) -> PostHogEvent? {
        PHObjCExceptionCatcher.invokeBlock(from: self, with: event) { exception in
            // The exception's name only: its reason can hold the values the hook was redacting.
            hedgeLog("Dropping event '\(event.event)': Objective-C beforeSend raised \(exception.name.rawValue).")
        } as? PostHogEvent
    }
}

/// ObjC wrapper for the logs `beforeSend` block. Use with
/// `PostHogLogsConfig.setBeforeSend(_:)`.
@objc public final class BoxedBeforeSendLogBlock: NSObject, Sendable {
    /// Wrapped log callback.
    @objc public let block: PostHogBeforeSendLogBlock

    /// Creates a boxed log callback for Objective-C callers.
    ///
    /// - Parameter block: Callback that can mutate or drop a log record.
    @objc(block:)
    public init(block: @escaping PostHogBeforeSendLogBlock) {
        self.block = block
    }

    func invokeSafely(with record: PostHogLogRecord) -> PostHogLogRecord? {
        PHObjCExceptionCatcher.invokeBlock(from: self, with: record) { exception in
            hedgeLog("Dropping a log: Objective-C beforeSend raised \(exception.name.rawValue).")
        } as? PostHogLogRecord
    }
}
