//
//  SwiftCrashTriggers.swift
//  PostHogExample
//
//  Swift-native crash triggers for testing crash reporting
//

import Foundation

/// Swift crash triggers with nested call stacks for testing stack trace capture
enum SwiftCrashTriggers {
    // MARK: - Public API

    static func triggerFatalError() {
        OuterLayer.processFatalError()
    }

    static func triggerPreconditionFailure() {
        OuterLayer.processPreconditionFailure()
    }

    static func triggerAssertionFailure() {
        OuterLayer.processAssertionFailure()
    }

    static func triggerForceUnwrapNil() {
        OuterLayer.processForceUnwrapNil()
    }

    // MARK: - Nested Layers for Deeper Stack Traces

    private enum OuterLayer {
        static func processFatalError() {
            MiddleLayer.handleFatalError()
        }

        static func processPreconditionFailure() {
            MiddleLayer.handlePreconditionFailure()
        }

        static func processAssertionFailure() {
            MiddleLayer.handleAssertionFailure()
        }

        static func processForceUnwrapNil() {
            MiddleLayer.handleForceUnwrapNil()
        }
    }

    private enum MiddleLayer {
        static func handleFatalError() {
            InnerLayer.executeFatalError()
        }

        static func handlePreconditionFailure() {
            InnerLayer.executePreconditionFailure()
        }

        static func handleAssertionFailure() {
            InnerLayer.executeAssertionFailure()
        }

        static func handleForceUnwrapNil() {
            InnerLayer.executeForceUnwrapNil()
        }
    }

    private enum InnerLayer {
        static func executeFatalError() {
            fatalError("Intentional fatalError for crash testing")
        }

        static func executePreconditionFailure() {
            preconditionFailure("Intentional preconditionFailure for crash testing")
        }

        static func executeAssertionFailure() {
            assertionFailure("Intentional assertionFailure for crash testing")
        }

        static func executeForceUnwrapNil() {
            let nilValue: String? = nil
            _ = nilValue!
        }
    }
}
