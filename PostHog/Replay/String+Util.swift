//
//  String+Util.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 21.03.24.
//

import Foundation

extension String {
    func mask() -> String {
        String(repeating: "*", count: count)
    }
}

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        (self ?? "").isEmpty
    }
}
