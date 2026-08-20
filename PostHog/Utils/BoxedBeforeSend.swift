//
//  BoxedBeforeSend.swift
//  PostHog
//

import Foundation
#if compiler(>=6.0)
    internal import PostHogObjCExceptionSupport
#else
    @_implementationOnly import PostHogObjCExceptionSupport
#endif

/// ObjC wrappers for the Swift function-typed `beforeSend` chains: Swift
/// function types aren't `@objc`-bridgeable, and `@objc` classes can't be
/// generic, so each function shape gets its own concrete box. Swift callers
/// use the variadic `setBeforeSend(_:)` overloads and never see these.

/// ObjC wrapper for the events `beforeSend` block. Use with
/// `PostHogConfig.setBeforeSend(_:)`.
@objc public final class BoxedBeforeSendBlock: NSObject {
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
            let reason = exception.reason ?? "No reason provided"
            hedgeLog("Objective-C beforeSend callback raised \(exception.name.rawValue): \(reason). The event was dropped.")
        } as? PostHogEvent
    }
}

/// ObjC wrapper for the logs `beforeSend` block. Use with
/// `PostHogLogsConfig.setBeforeSend(_:)`.
@objc public final class BoxedBeforeSendLogBlock: NSObject {
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
            let reason = exception.reason ?? "No reason provided"
            hedgeLog("Objective-C log beforeSend callback raised \(exception.name.rawValue): \(reason). The log was dropped.")
        } as? PostHogLogRecord
    }
}
