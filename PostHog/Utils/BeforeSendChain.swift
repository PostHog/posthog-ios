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
///
/// Reference type with an internal lock: `set` and `run` may be called from
/// any thread (e.g. host code reconfiguring the chain while the events queue
/// runs `runBeforeSend` on its dispatch queue), and we need each `run` to see
/// a coherent block snapshot rather than a torn assignment.
final class BeforeSendChain<T> {
    typealias Block = (T) -> T?

    private let lock = NSLock()
    private var block: Block = { $0 }

    func set(_ blocks: [Block]) {
        let composed: Block = { value in
            blocks.reduce(value) { acc, block in
                acc.flatMap(block)
            }
        }
        lock.withLock { self.block = composed }
    }

    func run(_ value: T) -> T? {
        let snapshot = lock.withLock { self.block }
        return snapshot(value)
    }
}
