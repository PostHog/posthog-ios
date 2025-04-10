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
        let allowsMultipleSelection: Bool
        let hasOpenChoiceQuestion: Bool
        let options: [String]

        @Binding var selectedOptions: Set<String>
        @Binding var openChoiceInput: String
        @State private var textFieldRect: CGRect = .zero
        @FocusState private var isTextFieldFocused: Bool

        var body: some View {
            VStack {
                ForEach(options, id: \.self) { option in
                    let isSelected = isSelected(option)

                    Button {
                        withAnimation(.linear(duration: 0.15)) {
                            setSelected(!isSelected, option: option)
                        }
                    } label: {
                        if isOpenChoice(option) {
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
                            .modifier(SurveyOptionStyle(isChecked: isSelected))
                            .coordinateSpace(name: "SurveyButton")
                        } else {
                            Text(option)
                                .modifier(SurveyOptionStyle(isChecked: isSelected))
                                .multilineTextAlignment(.leading)
                        }
                    }
                    // text field needs to overlay the Button so it can receive touches first when enabled
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

                let isOpenChoice = self.isOpenChoice(option)
                // requires a small delay since textfield is enabled/disabled based on `selectedOptions` state update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTextFieldFocused = isOpenChoice
                }
            } else {
                selectedOptions.remove(option)
            }
        }

        @ViewBuilder
        private func openChoiceField(_ option: String) -> some View {
            if isOpenChoice(option) {
                TextField("", text: $openChoiceInput)
                    .focused($isTextFieldFocused)
                    .foregroundColor(isSelected(option) ? Color.black : Color.black.opacity(0.5))
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

    @available(iOS 15.0, *)
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

    #if DEBUG
        @available(iOS 18.0, *)
        private struct TestView: View {
            @State var selectedOptions: Set<String> = []
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
