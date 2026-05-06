//
//  BeforeSendChain.swift
//  PostHog
//

import Foundation

/// Composable `(T) -> T?` pipeline shared by `PostHogConfig` (events) and
/// `PostHogLogsConfig` (logs). Blocks run in registration order; the first
/// `nil` short-circuits the rest and drops the value.
///
/// Held privately on each config and exposed through that config's
/// type-specific `setBeforeSend(_:)` / `runBeforeSend(_:)` methods. The
/// per-config public API stays where it is so callers see typed signatures.
struct BeforeSendChain<T> {
    typealias Block = (T) -> T?

    private var block: Block = { $0 }

    mutating func set(_ blocks: [Block]) {
        block = { value in
            blocks.reduce(value) { acc, block in
                acc.flatMap(block)
            }
        }
    }

    func run(_ value: T) -> T? {
        block(value)
    }
}
