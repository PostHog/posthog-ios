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
    
    static func triggerThrowingFunction() {
        OuterLayer.triggerThrowingFunction()
    }

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

    static func triggerArrayOutOfBounds() {
        OuterLayer.processArrayOutOfBounds()
    }

    static func triggerImplicitUnwrapNil() {
        OuterLayer.processImplicitUnwrapNil()
    }

    // MARK: - Nested Classes for Deeper Stack Traces

    private enum OuterLayer {
        static func triggerThrowingFunction() {
            MiddleLayer.triggerThrowingFunction()
        }
        
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

        static func processArrayOutOfBounds() {
            MiddleLayer.handleArrayOutOfBounds()
        }

        static func processImplicitUnwrapNil() {
            MiddleLayer.handleImplicitUnwrapNil()
        }
    }

    private enum MiddleLayer {
        static func triggerThrowingFunction() {
            InnerLayer.triggerThrowingFunction()
        }
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

        static func handleArrayOutOfBounds() {
            InnerLayer.executeArrayOutOfBounds()
        }

        static func handleImplicitUnwrapNil() {
            InnerLayer.executeImplicitUnwrapNil()
        }
    }

    private enum InnerLayer {
        static func triggerThrowingFunction() {
            try! throwingFunction()
        }
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

        static func executeArrayOutOfBounds() {
            let array = [1, 2, 3]
            _ = array[10]
        }

        static func executeImplicitUnwrapNil() {
            let nilValue: String! = nil
            _ = nilValue.count
        }
        
        static func throwingFunction() throws -> Void {
            throw MyCustomError()
        }
    }
}

struct MyCustomError: Error {}
