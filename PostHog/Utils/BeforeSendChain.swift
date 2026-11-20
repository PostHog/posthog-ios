//
//  BeforeSendChain.swift
//  PostHog
//

import Foundation

/// Composable `@Sendable (T) -> T?` pipeline shared by the events and logs configs.
/// Blocks run in registration order; the first `nil` drops the value.
/// Reference type so concurrent `set` / `run` see a coherent block snapshot.
final class BeforeSendChain<T> {
    // @Sendable to match the public block types: converting their arrays to a
    // non-Sendable element type fails at runtime (`_arrayForceCast`).
    typealias Block = @Sendable (T) -> T?

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

    /// Wraps each non-Sendable block in a box instead of force-casting the array,
    /// which traps at runtime in Swift 5 mode.
    static func wrapping(_ blocks: [(T) -> T?]) -> [Block] {
        blocks.map { block in
            let box = UncheckedSendableBlock(block)
            return { value in box.block(value) }
        }
    }
}

/// The app owns the thread safety of what its callback captures.
private final class UncheckedSendableBlock<T>: @unchecked Sendable {
    let block: (T) -> T?

    init(_ block: @escaping (T) -> T?) {
        self.block = block
    }
}
