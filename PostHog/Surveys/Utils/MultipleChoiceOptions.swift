//
//  Untitled.swift
//  PostHog
//
//  Created by Ioannis Josephides on 11/03/2025.
//

#if os(iOS)
    import SwiftUI

    struct MultipleChoiceOptions: View {
        let allowsMultipleSelection: Bool
        let hasOpenChoiceQuestion: Bool
        let options: [String]

        @State var selectedOptions: Set<String> = []
        @State private var openChoiceResponse: String = ""
        @State private var textFieldRect: CGRect = .zero
        @State private var isTextFieldFocused: Bool = false

        var body: some View {
            VStack {
                ForEach(options, id: \.self) { option in
                    let isSelected = isSelected(option)

                    Button(action: {
                        withAnimation(.linear(duration: 0.15)) {
                            setSelected(!isSelected, option: option)
                        }
                    }) {
                        if isOpenChoice(option) {
                            VStack(alignment: .leading) {
                                Text("\(option):")
                                Text("text-field-placeholder")
                                    .opacity(0)
                                    .frame(maxWidth: .infinity)
                                    .readFrame(in: .named("SurveyButton"), onChange: { rect in
                                        textFieldRect = rect
                                    })
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(SurveyOptionStyle(isChecked: isSelected))
                            .coordinateSpace(name: "SurveyButton")
                        } else {
                            Text(option)
                                .modifier(SurveyOptionStyle(isChecked: isSelected))
                        }
                    }
                    .overlay(openChoiceField(option), alignment: .topLeading)
                }
            }
        }

        private func isOpenChoice(_ option: String) -> Bool {
            hasOpenChoiceQuestion && options.last == option
        }

        private func isSelected(_ option: String) -> Bool {
            selectedOptions.contains(option)
        }

        private func setSelected(_ selected: Bool, option: String) {
            if selected {
                if allowsMultipleSelection {
                    selectedOptions.insert(option)
                } else {
                    selectedOptions = [option]
                }

                isTextFieldFocused = isOpenChoice(option)
            } else {
                selectedOptions.remove(option)
                isTextFieldFocused = false
            }
        }

        @ViewBuilder
        private func openChoiceField(_ option: String) -> some View {
            if isOpenChoice(option) {
                LegacyTextField(text: $openChoiceResponse)
                    .focused($isTextFieldFocused)
                    .foregroundColor(isSelected(option) ? UIColor.black : UIColor.black.withAlphaComponent(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxWidth: textFieldRect.size.width)
                    .disabled(!isSelected(option))
                    .offset(
                        x: textFieldRect.origin.x,
                        y: textFieldRect.origin.y
                    )
            }
        }
    }

    private struct SurveyOptionStyle: ViewModifier {
        let isChecked: Bool

        func body(content: Content) -> some View {
            HStack(alignment: .center, spacing: 8) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(isChecked ? .body.bold() : .body)
                    .animation(.linear(duration: 0.15), value: isChecked)

                if isChecked {
                    CheckIcon()
                        .frame(width: 16, height: 12)
                }
            }
            .contentShape(Rectangle())
            .padding(10)
            .frame(minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isChecked ? Color.black : Color.black.opacity(0.5), lineWidth: 1)
            )
            .foregroundColor(isChecked ? Color.black : Color.black.opacity(0.5))
            .contentShape(Rectangle())
        }
    }

    #Preview {
        MultipleChoiceOptions(
            allowsMultipleSelection: true,
            hasOpenChoiceQuestion: true,
            options: [
                "Tutorials",
                "Customer case studies",
                "Product announcements",
                "Other",
            ]
        )
        .colorScheme(.dark)
        .padding()
    }

#endif
