//
//  RageClickControlsSwiftUIView.swift
//  PostHogExample
//
//  SwiftUI counterpart to RageClickControlsView. SwiftUI controls don't always bridge to the
//  UIKit class you'd expect, so use this screen (with `config.debug = true`) to discover which
//  controls are actually skipped. Each label notes the expected UIKit class.
//

#if os(iOS)
    import PostHog
    import SwiftUI

    struct RageClickControlsSwiftUIView: View {
        @State private var text = ""
        @State private var editorText = "Double- or triple-tap to select text here."
        @State private var search = ""
        @State private var stepperValue = 0
        @State private var sliderValue = 0.5
        @State private var date = Date()
        @State private var pickerSelection = 0
        @State private var segment = 0
        @State private var toggleOn = false
        @State private var page = 0
        @State private var counter = 0

        private let options = ["One", "Two", "Three", "Four", "Five"]

        var body: some View {
            Form {
                Section {
                    Text("Rapidly tap each control three times. With debug logging on, a control is "
                        + "\"skipped\" when no $rageclick appears in the console. Labels note the UIKit "
                        + "class each is expected to bridge to. The search bar lives in the navigation bar.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("Expected to block — text") {
                    row("TextField → UITextField") {
                        TextField("Tap to edit", text: $text)
                    }
                    row("TextEditor → UITextView") {
                        TextEditor(text: $editorText)
                            .frame(height: 80)
                    }
                }

                Section("Expected to block — adjusters / navigation") {
                    row("Stepper → UIStepper?") {
                        Stepper("Value: \(stepperValue)", value: $stepperValue)
                    }
                    row("Slider → UISlider?") {
                        Slider(value: $sliderValue)
                    }
                    row("DatePicker(.wheel) → UIDatePicker") {
                        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                    }
                    row("Picker(.wheel) → UIPickerView") {
                        Picker("Pick", selection: $pickerSelection) {
                            ForEach(options.indices, id: \.self) { Text(options[$0]).tag($0) }
                        }
                        .pickerStyle(.wheel)
                    }
                    row("Picker(.segmented) → UISegmentedControl") {
                        Picker("Segment", selection: $segment) {
                            Text("Prev").tag(0)
                            Text("Mid").tag(1)
                            Text("Next").tag(2)
                        }
                        .pickerStyle(.segmented)
                    }
                    row("TabView(.page) dots → UIPageControl") {
                        TabView(selection: $page) {
                            ForEach(0 ..< 5, id: \.self) { index in
                                Text("Page \(index + 1)").tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .frame(height: 120)
                    }
                }

                Section("Marker opt-out") {
                    // In SwiftUI use `.postHogNoRageClick()`; accessibility-id markers don't reach
                    // a view/layer the touch path can read.
                    row("Button + .postHogNoRageClick()") {
                        Button(action: {}) {
                            tappableBox("Tap rapidly (marked)")
                        }
                        .buttonStyle(.plain)
                        .postHogNoRageClick()
                    }
                }

                Section("Should STILL emit $rageclick — eligible") {
                    row("Toggle → UISwitch") {
                        Toggle("Toggle", isOn: $toggleOn)
                    }
                    Button("Rage-tap me — SHOULD emit $rageclick (taps: \(counter))") {
                        counter += 1
                    }
                    .foregroundColor(.red)
                }
            }
            .searchable(text: $search, prompt: "Searchable → UISearchBar")
            .navigationTitle("Rage Click Control (SwiftUI)")
            .navigationBarTitleDisplayMode(.inline)
        }

        private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                content()
            }
        }

        private func tappableBox(_ title: String) -> some View {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
        }
    }
#endif
