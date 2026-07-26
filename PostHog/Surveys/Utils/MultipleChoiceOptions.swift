//
//  MultipleChoiceOptions.swift
//  PostHog
//
//  Created by Ioannis Josephides on 11/03/2025.
//

#if os(iOS)
    import SwiftUI

    @available(iOS 15.0, *)
    struct MultipleChoiceOptions: View {
        @Environment(\.surveyAppearance) private var appearance

        let allowsMultipleSelection: Bool
        let hasOpenChoiceQuestion: Bool
        let options: [String]

        // Selection is keyed by choice index, not label text, so an in-place content swap
        // (e.g. re-translating the survey) keeps the same options selected and the caller reads
        // the current-language label at submit time.
        @Binding var selectedOptions: Set<Int>
        @Binding var openChoiceInput: String
        @State private var textFieldRect: CGRect = .zero
        @FocusState private var isTextFieldFocused: Bool

        private var inputTextColor: Color {
            appearance.effectiveInputTextColor
        }

        var body: some View {
            VStack {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    let isSelected = isSelected(index)

                    Button {
                        withAnimation(.linear(duration: 0.15)) {
                            setSelected(!isSelected, index: index)
                        }
                    } label: {
                        if isOpenChoice(index) {
                            VStack(alignment: .leading) {
                                Text("\(option):")
                                    .multilineTextAlignment(.leading)
                                // Invisible text for calculating TextField placement
                                Text("text-field-placeholder")
                                    .opacity(0)
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.leading)
                                    .readFrame(in: .named("SurveyButton")) { frame in
                                        textFieldRect = frame
                                    }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(SurveyOptionStyle(isChecked: isSelected, textColor: inputTextColor))
                            .coordinateSpace(name: "SurveyButton")
                        } else {
                            Text(option)
                                .modifier(SurveyOptionStyle(isChecked: isSelected, textColor: inputTextColor))
                                .multilineTextAlignment(.leading)
                        }
                    }
                    // text field needs to overlay the Button so it can receive touches first when enabled
                    .overlay(openChoiceField(index), alignment: .topLeading)
                }
            }
        }

        private func isOpenChoice(_ index: Int) -> Bool {
            hasOpenChoiceQuestion && index == options.count - 1
        }

        private func isSelected(_ index: Int) -> Bool {
            selectedOptions.contains(index)
        }

        private func setSelected(_ selected: Bool, index: Int) {
            if selected {
                if allowsMultipleSelection {
                    selectedOptions.insert(index)
                } else {
                    selectedOptions = [index]
                }

                let isOpenChoice = self.isOpenChoice(index)
                // requires a small delay since textfield is enabled/disabled based on `selectedOptions` state update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTextFieldFocused = isOpenChoice
                }
            } else {
                selectedOptions.remove(index)
            }
        }

        @ViewBuilder
        private func openChoiceField(_ index: Int) -> some View {
            if isOpenChoice(index) {
                TextField("", text: $openChoiceInput)
                    .focused($isTextFieldFocused)
                    .foregroundColor(isSelected(index) ? inputTextColor : inputTextColor.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxWidth: textFieldRect.size.width)
                    .disabled(!isSelected(index))
                    .offset(
                        x: textFieldRect.origin.x,
                        y: textFieldRect.origin.y
                    )
            }
        }
    }

    @available(iOS 15.0, *)
    private struct SurveyOptionStyle: ViewModifier {
        let isChecked: Bool
        let textColor: Color

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
                    .stroke(isChecked ? textColor : textColor.opacity(0.5), lineWidth: 1)
            )
            .foregroundColor(isChecked ? textColor : textColor.opacity(0.5))
            .contentShape(Rectangle())
        }
    }

    #if DEBUG
        @available(iOS 18.0, *)
        private struct TestView: View {
            @State var selectedOptions: Set<Int> = []
            @State var openChoiceInput = ""

            var body: some View {
                MultipleChoiceOptions(
                    allowsMultipleSelection: true,
                    hasOpenChoiceQuestion: true,
                    options: [
                        "Tutorials",
                        "Customer case studies",
                        "Product announcements",
                        "Other",
                    ],
                    selectedOptions: $selectedOptions,
                    openChoiceInput: $openChoiceInput
                )
                .colorScheme(.dark)
                .padding()
            }
        }

        @available(iOS 18.0, *)
        #Preview {
            TestView()
        }
    #endif
#endif
