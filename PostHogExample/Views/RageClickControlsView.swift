//
//  RageClickControlsView.swift
//  PostHogExample
//
//  A manual test screen for rage click suppression.
//
//  Every control here is one where rapid repeated taps are intentional, so the SDK should NOT emit
//  a `$rageclick`. With `config.debug = true`, watch the console: rapidly tapping any control below
//  three times in the same spot should produce no `$rageclick` — except the red button at the
//  bottom (an eligible control), which should.
//
//  The controls are built in UIKit on purpose: suppression keys off the real UIKit class of the
//  tapped view, which SwiftUI controls don't reliably bridge to.
//

#if os(iOS)
    import PostHog
    import SwiftUI
    import UIKit

    struct RageClickControlsView: View {
        var body: some View {
            RepresentedRageClickControls()
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Rage Click Control (UIKit)")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private struct RepresentedRageClickControls: UIViewControllerRepresentable {
        func makeUIViewController(context _: Context) -> RageClickControlsViewController {
            RageClickControlsViewController()
        }

        func updateUIViewController(_: RageClickControlsViewController, context _: Context) {}
    }

    final class RageClickControlsViewController: UIViewController {
        private let pickerData = ["One", "Two", "Three", "Four", "Five"]

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground

            let stack = UIStackView()
            stack.axis = .vertical
            stack.spacing = 24
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.isLayoutMarginsRelativeArrangement = true
            stack.directionalLayoutMargins = .init(top: 20, leading: 20, bottom: 40, trailing: 20)

            let scroll = UIScrollView()
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.keyboardDismissMode = .interactive
            view.addSubview(scroll)
            scroll.addSubview(stack)

            NSLayoutConstraint.activate([
                scroll.topAnchor.constraint(equalTo: view.topAnchor),
                scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            ])

            stack.addArrangedSubview(makeHeader())

            // MARK: Controls that should BLOCK rage clicks

            let textField = UITextField()
            textField.placeholder = "Tap to edit / double-tap to select"
            textField.borderStyle = .roundedRect
            stack.addArrangedSubview(labeled("UITextField", textField))

            let textView = UITextView()
            textView.text = "Double- or triple-tap to select text here. Rapid taps are intentional, not frustration."
            textView.font = .preferredFont(forTextStyle: .body)
            textView.isScrollEnabled = false
            textView.layer.borderWidth = 1
            textView.layer.borderColor = UIColor.separator.cgColor
            textView.layer.cornerRadius = 8
            textView.heightAnchor.constraint(equalToConstant: 90).isActive = true
            stack.addArrangedSubview(labeled("UITextView", textView))

            let searchBar = UISearchBar()
            searchBar.placeholder = "Search"
            stack.addArrangedSubview(labeled("UISearchBar", searchBar))

            let stepper = UIStepper()
            stack.addArrangedSubview(labeled("UIStepper (+ / −)", stepper))

            let slider = UISlider()
            slider.value = 0.5
            stack.addArrangedSubview(labeled("UISlider", slider))

            let datePicker = UIDatePicker()
            datePicker.preferredDatePickerStyle = .wheels
            stack.addArrangedSubview(labeled("UIDatePicker (wheels)", datePicker))

            let picker = UIPickerView()
            picker.dataSource = self
            picker.delegate = self
            stack.addArrangedSubview(labeled("UIPickerView", picker))

            let segmented = UISegmentedControl(items: ["Prev", "Mid", "Next"])
            segmented.selectedSegmentIndex = 0
            stack.addArrangedSubview(labeled("UISegmentedControl", segmented))

            let pageControl = UIPageControl()
            pageControl.numberOfPages = 5
            pageControl.currentPage = 0
            pageControl.pageIndicatorTintColor = .systemGray3
            pageControl.currentPageIndicatorTintColor = .systemBlue
            stack.addArrangedSubview(labeled("UIPageControl", pageControl))

            // MARK: Marker opt-out (a custom control tagged ph-no-rageclick)

            let markerButton = makeBlockButton(title: "Custom control — tap rapidly")
            markerButton.accessibilityIdentifier = "ph-no-rageclick"
            stack.addArrangedSubview(labeled("UIButton tagged \"ph-no-rageclick\"", markerButton))

            // MARK: Eligible control (SHOULD still emit $rageclick) — for contrast

            let eligibleButton = makeBlockButton(title: "Rage-tap me — SHOULD emit $rageclick")
            eligibleButton.setTitleColor(.systemRed, for: .normal)
            eligibleButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.12)
            stack.addArrangedSubview(labeled("Plain UIButton (eligible — control case)", eligibleButton))
        }

        // MARK: - Helpers

        private func makeHeader() -> UIView {
            let label = UILabel()
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .footnote)
            label.textColor = .secondaryLabel
            label.text = "Rapidly tap each control three times in the same spot. With debug logging on, "
                + "none of these should emit a $rageclick — except the red button at the bottom, which should."
            return label
        }

        private func labeled(_ title: String, _ control: UIView) -> UIView {
            let row = UIStackView(arrangedSubviews: [makeTitle(title), control])
            row.axis = .vertical
            row.spacing = 6
            return row
        }

        private func makeTitle(_ text: String) -> UILabel {
            let label = UILabel()
            label.text = text
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.textColor = .label
            return label
        }

        private func makeBlockButton(title: String) -> UIButton {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.backgroundColor = .secondarySystemBackground
            button.layer.cornerRadius = 8
            button.heightAnchor.constraint(equalToConstant: 50).isActive = true
            return button
        }
    }

    extension RageClickControlsViewController: UIPickerViewDataSource, UIPickerViewDelegate {
        func numberOfComponents(in _: UIPickerView) -> Int {
            1
        }

        func pickerView(_: UIPickerView, numberOfRowsInComponent _: Int) -> Int {
            pickerData.count
        }

        func pickerView(_: UIPickerView, titleForRow row: Int, forComponent _: Int) -> String? {
            pickerData[row]
        }
    }
#endif
