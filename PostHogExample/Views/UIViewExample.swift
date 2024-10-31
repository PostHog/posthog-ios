//
//  UIViewExample.swift
//  PostHogExample
//
//  Created by Ben White on 17.03.23.
//

import Foundation
import SwiftUI
import UIKit

class ExampleUIView: UIView {
    private var label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .title1)
        label.text = "Sensitive information!"
        label.textAlignment = .center

        return label
    }()

    init() {
        super.init(frame: .zero)
        backgroundColor = .systemPink
        accessibilityIdentifier = "ph-no-capture"

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct RepresentedExampleUIView: UIViewRepresentable {
    typealias UIViewType = ExampleUIView

    func makeUIView(context _: Context) -> ExampleUIView {
        let view = ExampleUIView()

        // Do some configurations here if needed.
        return view
    }

    func updateUIView(_: ExampleUIView, context _: Context) {
        // Updates the state of the specified view controller with new information from SwiftUI.
    }
}
