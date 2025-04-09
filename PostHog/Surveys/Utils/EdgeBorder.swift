//
//  EdgeBorder.swift
//  PostHog
//
//  Created by Ioannis Josephides on 22/03/2025.
//

#if os(iOS)
    import SwiftUI

    struct EdgeBorder: Shape {
        var lineWidth: CGFloat
        var edges: [Edge]

        func path(in rect: CGRect) -> Path {
            edges.map { edge -> Path in
                switch edge {
                case .top: return Path(.init(x: rect.minX, y: rect.minY, width: rect.width, height: lineWidth))
                case .bottom: return Path(.init(x: rect.minX, y: rect.maxY - lineWidth, width: rect.width, height: lineWidth))
                case .leading: return Path(.init(x: rect.minX, y: rect.minY, width: lineWidth, height: rect.height))
                case .trailing: return Path(.init(x: rect.maxX - lineWidth, y: rect.minY, width: lineWidth, height: rect.height))
                }
            }.reduce(into: Path()) { $0.addPath($1) }
        }
    }
#endif
