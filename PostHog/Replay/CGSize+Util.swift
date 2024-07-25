//
//  CGSize+Util.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 24.07.24.
//

import Foundation

#if os(iOS)
    extension CGSize {
        func hasSize() -> Bool {
            if width == 0 || height == 0 {
                return false
            }
            return true
        }
    }
#endif
