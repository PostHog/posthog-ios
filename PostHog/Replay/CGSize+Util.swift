//
//  CGSize+Util.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 24.07.24.
//

#if os(iOS)
    import Foundation

    extension CGSize {
        func hasSize() -> Bool {
            if width == 0 || height == 0 {
                return false
            }
            return true
        }
    }
#endif
