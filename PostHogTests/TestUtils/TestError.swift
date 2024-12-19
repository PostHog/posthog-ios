//
//  TestError.swift
//  PostHog
//
//  Created by Yiannis Josephides on 18/12/2024.
//

struct TestError: Error, ExpressibleByStringLiteral, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }

    init(stringLiteral value: StringLiteralType) {
        description = value
    }
}
