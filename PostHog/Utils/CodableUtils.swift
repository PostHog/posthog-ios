//
//  CodableUtils.swift
//  PostHog
//
//  Created by Ben White on 17.02.23.
//

import Foundation

@propertyWrapper
public struct CodableIgnored<T>: Codable {
    public var wrappedValue: T?

    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }

    public init(from _: Decoder) throws {
        wrappedValue = nil
    }

    public func encode(to _: Encoder) throws {
        // Do nothing
    }
}

public extension KeyedDecodingContainer {
    func decode<T>(
        _: CodableIgnored<T>.Type,
        forKey _: Self.Key
    ) throws -> CodableIgnored<T> {
        CodableIgnored(wrappedValue: nil)
    }
}

public extension KeyedEncodingContainer {
    mutating func encode<T>(
        _: CodableIgnored<T>,
        forKey _: KeyedEncodingContainer<K>.Key
    ) throws {
        // Do nothing
    }
}
