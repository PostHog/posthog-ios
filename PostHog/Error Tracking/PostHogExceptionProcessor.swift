//
//  PostHogExceptionProcessor.swift
//  PostHog
//
//  Created by Ioannis Josephides on 14/11/2025.
//

import Darwin
import Foundation

/// Processes errors and exceptions into PostHog's $exception event format
///
/// This class converts Swift Error and NSException instances into PostHog exception event properties.
///
/// **Note on Binary Images:**
/// Currently, binary images (debug metadata) are NOT included in exception events.
/// This is intentional until server-side symbolication is implemented. Binary images
/// would be needed for server-side symbolication of raw instruction addresses, but
/// without that capability, we won't know exactly what's needed or if there's something that can be reused from PLCrashReporter lib.
/// When server-side symbolication is added, we should include binary images
///
enum PostHogExceptionProcessor {
    // MARK: - Public API

    /// Convert Error/NSError to properties
    ///
    /// - Parameters:
    ///   - error: The error to convert
    ///   - handled: Whether the error was caught/handled
    ///   - mechanismType: The mechanism that captured the error (e.g., "generic", "NSException")
    ///   - config: Error tracking configuration for in-app detection
    /// - Returns: Dictionary of properties in PostHog's $exception event format
    static func errorToProperties(
        _ error: Error,
        handled: Bool,
        mechanismType: String,
        config: PostHogErrorTrackingConfig
    ) -> [String: Any] {
        var properties: [String: Any] = [:]

        properties["$exception_level"] = "error" // TODO: figure this out from error wrapped type

        let exceptions = buildExceptionList(
            from: error,
            handled: handled,
            mechanismType: mechanismType,
            config: config
        )

        if !exceptions.isEmpty {
            properties["$exception_list"] = exceptions
        }

        return properties
    }

    /// Convert NSException to properties
    ///
    /// Note: Uses the exception's own stack trace (`callStackReturnAddresses`) if available,
    /// otherwise falls back to capturing the current thread's stack (synthetic).
    ///
    /// - Parameters:
    ///   - exception: The NSException to convert
    ///   - handled: Whether the exception was caught/handled
    ///   - mechanismType: The mechanism type for categorizing the exception
    ///   - config: Error tracking configuration for in-app detection
    /// - Returns: Dictionary of properties in PostHog's $exception event format
    static func exceptionToProperties(
        _ exception: NSException,
        handled: Bool,
        mechanismType: String,
        config: PostHogErrorTrackingConfig
    ) -> [String: Any] {
        var properties: [String: Any] = [:]
        properties["$exception_level"] = "error" // TODO: figure this out from error wrapped type

        let exceptions = buildExceptionList(
            from: exception,
            handled: handled,
            mechanismType: mechanismType,
            config: config
        )

        if !exceptions.isEmpty {
            properties["$exception_list"] = exceptions
        }

        return properties
    }

    /// Convert a message string to properties
    ///
    /// - Parameters:
    ///   - message: The error message to convert
    ///   - type: Optional exception type name (defaults to "String")
    ///   - config: Error tracking configuration for in-app detection
    /// - Returns: Dictionary of properties in PostHog's $exception event format
    static func messageToProperties(
        _ message: String,
        config: PostHogErrorTrackingConfig
    ) -> [String: Any] {
        var properties: [String: Any] = [:]

        properties["$exception_level"] = "error"

        var exception: [String: Any] = [:]
        exception["type"] = "Message"
        exception["value"] = message
        exception["thread_id"] = Thread.current.threadId

        exception["mechanism"] = [
            "type": "generic-message",
            "handled": true,
            "synthetic": true,
        ]

        if let stacktrace = buildStacktrace(config: config) {
            exception["stacktrace"] = stacktrace
        }

        properties["$exception_list"] = [exception]

        return properties
    }

    // MARK: - Internal Exception Building

    /// Build list of exceptions from NSException chain
    ///
    /// Walks the NSException chain via NSUnderlyingErrorKey to capture all related exceptions.
    /// The list is ordered from root exception to underlying exceptions (same as Android).
    private static func buildExceptionList(
        from exception: NSException,
        handled: Bool,
        mechanismType: String,
        config: PostHogErrorTrackingConfig
    ) -> [[String: Any]] {
        var exceptions: [[String: Any]] = []
        var nsExceptions: [NSException] = []

        // Walk exception chain via NSUnderlyingErrorKey
        nsExceptions.append(exception)

        var current = exception
        while let underlying = current.userInfo?[NSUnderlyingErrorKey] as? NSException {
            nsExceptions.append(underlying)
            current = underlying
        }

        // Build exceptions (same order as Android)
        for exc in nsExceptions {
            if let exceptionDict = buildException(
                from: exc,
                handled: handled,
                mechanismType: mechanismType,
                config: config
            ) {
                exceptions.append(exceptionDict)
            }
        }

        return exceptions
    }

    /// Build list of exceptions from error chain
    ///
    /// Walks the error chain via NSUnderlyingErrorKey to capture all related errors.
    /// The list is ordered from root error to underlying errors (same as Android).
    private static func buildExceptionList(
        from error: Error,
        handled: Bool,
        mechanismType: String,
        config: PostHogErrorTrackingConfig
    ) -> [[String: Any]] {
        var exceptions: [[String: Any]] = []
        var errors: [NSError] = []

        // Walk error chain via NSUnderlyingErrorKey
        let nsError = error as NSError
        errors.append(nsError)

        var current = nsError
        while let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError {
            errors.append(underlying)
            current = underlying
        }

        // Build exceptions (same order as Android)
        for err in errors {
            if let exception = buildException(
                from: err,
                handled: handled,
                mechanismType: mechanismType,
                config: config
            ) {
                exceptions.append(exception)
            }
        }

        return exceptions
    }

    /// Build a single exception dictionary from an NSError
    private static func buildException(
        from error: NSError,
        handled: Bool,
        mechanismType: String,
        config: PostHogErrorTrackingConfig
    ) -> [String: Any]? {
        var exception: [String: Any] = [:]

        exception["type"] = error.domain

        if let message = extractErrorMessage(from: error) {
            exception["value"] = message
        }

        if let module = extractModule(from: error) {
            exception["module"] = module
        }

        exception["thread_id"] = Thread.current.threadId

        exception["mechanism"] = [
            "type": mechanismType,
            "handled": handled,
            "synthetic": false,
        ]

        if let stacktrace = buildStacktrace(config: config) {
            exception["stacktrace"] = stacktrace
        }

        return exception
    }

    /// Build a single exception dictionary from an NSException
    private static func buildException(
        from exception: NSException,
        handled: Bool,
        mechanismType: String,
        config: PostHogErrorTrackingConfig
    ) -> [String: Any]? {
        var exceptionDict: [String: Any] = [:]

        exceptionDict["type"] = exception.name.rawValue
        exceptionDict["value"] = exception.reason ?? "Unknown exception"
        exceptionDict["thread_id"] = Thread.current.threadId

        // Use exception's real stack if available, otherwise capture current (synthetic)
        let exceptionAddresses = exception.callStackReturnAddresses
        let isSynthetic: Bool
        let stacktrace: [String: Any]?

        if !exceptionAddresses.isEmpty {
            // Use exception's actual stack trace (captured when exception was raised)
            stacktrace = buildStacktraceFromAddresses(exceptionAddresses, config: config)
            isSynthetic = false
        } else {
            // Fall back to current stack (synthetic - captured at reporting site)
            stacktrace = buildStacktrace(config: config)
            isSynthetic = true
        }

        exceptionDict["mechanism"] = [
            "type": mechanismType,
            "handled": handled,
            "synthetic": isSynthetic,
        ]

        if let stacktrace = stacktrace {
            exceptionDict["stacktrace"] = stacktrace
        }

        return exceptionDict
    }

    // MARK: - Error Message Extraction

    /// Extract user-friendly error message
    ///
    /// Priority:
    /// 1. NSDebugDescriptionErrorKeyf
    /// 2. NSLocalizedDescriptionKey
    /// 3. Code only
    private static func extractErrorMessage(from error: NSError) -> String? {
        if let debugDesc = error.userInfo[NSDebugDescriptionErrorKey] as? String {
            return "\(debugDesc) (Code: \(error.code))"
        }

        if let localizedDesc = error.userInfo[NSLocalizedDescriptionKey] as? String {
            return "\(localizedDesc) (Code: \(error.code))"
        }

        return "Code: \(error.code)"
    }

    /// Extract module name from error domain
    private static func extractModule(from error: NSError) -> String? {
        let domain = error.domain
        return domain.contains(".") ? domain : nil
    }

    // MARK: - Stack Trace Capture

    /// Build stacktrace dictionary from current thread (synthetic)
    static func buildStacktrace(config: PostHogErrorTrackingConfig) -> [String: Any]? {
        let frames = PostHogStackTrace.captureCurrentStackTraceWithMetadata(config: config, skipFrames: 3)
        
        guard !frames.isEmpty else { return nil }

        return [
            "frames": frames,
            "type": "raw",
        ]
    }

    /// Build stacktrace dictionary from raw addresses (e.g., NSException.callStackReturnAddresses)
    ///
    /// This produces a non-synthetic stack trace since the addresses come from the actual
    /// exception rather than being captured at the reporting site.
    ///
    /// - Parameters:
    ///   - addresses: Array of return addresses (from NSException.callStackReturnAddresses)
    ///   - config: Error tracking configuration for in-app detection
    /// - Returns: Stacktrace dictionary or nil if no frames
    static func buildStacktraceFromAddresses(
        _ addresses: [NSNumber],
        config: PostHogErrorTrackingConfig
    ) -> [String: Any]? {
        let frames = PostHogStackTrace.symbolicateAddresses(addresses, config: config, skipFrames: 0)
        
        guard !frames.isEmpty else { return nil }

        return [
            "frames": frames,
            "type": "raw",
        ]
    }

}

private extension Thread {
    /// Get the current thread's Mach thread ID
    var threadId: Int {
        Int(pthread_mach_thread_np(pthread_self()))
    }
}
