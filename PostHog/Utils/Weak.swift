//
//  Weak.swift
//  PostHog
//
//  Created by Yiannis Josephides on 31/01/2025.
//

/**
 Boxing a weak reference to a reference type.
 */
struct Weak<T: AnyObject> {
    weak var value: T?

    public init(_ wrappedValue: T? = nil) {
        value = wrappedValue
    }
}
