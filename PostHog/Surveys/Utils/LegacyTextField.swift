//
//  LegacyTextField.swift
//  PostHog
//
//  Created by Ioannis Josephides on 11/03/2025.
//

#if os(iOS)
    import SwiftUI
    import UIKit

    /**
     Note: `FocusState` was introduced in iOS15+

     Since we want to support iOS13+, we have to roll out our backport for UITextField with the ability to receive focus and lose focus from SwiftUI
     */
    struct LegacyTextField: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.layoutDirection) private var layoutDirection: LayoutDirection

        @Binding var text: String
        @Binding var focused: Bool

        var onEditingChanged: (Bool) -> Void = { _ in }
        var onCommit: () -> Void = {}

        private var font: UIFont = .preferredFont(forTextStyle: .body)
        private var returnKeyType: UIReturnKeyType = .default
        private var keyboardType: UIKeyboardType = .default
        private var foregroundColor: UIColor?
        private var contentType: UITextContentType?
        private var autocorrection: UITextAutocorrectionType = .default
        private var autocapitalization: UITextAutocapitalizationType = .sentences
        private var isSecure: Bool = false

        init(text: Binding<String>,
             focused: Binding<Bool> = .constant(false),
             onEditingChanged: @escaping (Bool) -> Void = { _ in },
             onCommit: @escaping () -> Void = {})
        {
            _text = text
            _focused = focused
            self.onEditingChanged = onEditingChanged
            self.onCommit = onCommit
        }

        var body: some View {
            UITextFieldWrapper(
                text: $text,
                focused: $focused,
                returnKeyType: returnKeyType,
                keyboardType: keyboardType,
                font: font,
                foregroundColor: foregroundColor,
                contentType: contentType,
                autocorrection: autocorrection,
                autocapitalization: autocapitalization,
                isSecure: isSecure,
                isUserInteractionEnabled: isEnabled,
                onEditingChanged: onEditingChanged,
                onCommit: onCommit
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    extension LegacyTextField {
        func foregroundColor(_ color: UIColor?) -> some View {
            var view = self
            view.foregroundColor = color
            return view
        }

        func font(_ font: UIFont?) -> some View {
            var view = self
            view.font = font ?? UIFont.preferredFont(forTextStyle: .body)
            return view
        }

        func textContentType(_ textContentType: UITextContentType?) -> some View {
            var view = self
            view.contentType = textContentType
            return view
        }

        func disableAutocorrection(_ disable: Bool?) -> some View {
            var view = self
            if let disable = disable {
                view.autocorrection = disable ? .no : .yes
            } else {
                view.autocorrection = .default
            }
            return view
        }

        func autocapitalization(_ style: UITextAutocapitalizationType) -> some View {
            var view = self
            view.autocapitalization = style
            return view
        }

        func isSecure(_ isSecure: Bool) -> some View {
            var view = self
            view.isSecure = isSecure
            return view
        }

        func returnKey(_ style: UIReturnKeyType) -> Self {
            var view = self
            view.returnKeyType = style
            return view
        }

        func keyboardType(_ type: UIKeyboardType) -> Self {
            var view = self
            view.keyboardType = type
            return view
        }

        func focused(_ value: Binding<Bool>) -> Self {
            var view = self
            view._focused = value
            return view
        }
    }

    fileprivate struct UITextFieldWrapper: UIViewRepresentable {
        @Binding var text: String

        var onEditingChanged: (Bool) -> Void = { _ in }
        var onCommit: () -> Void = {}

        private var returnKeyType: UIReturnKeyType
        private var keyboardType: UIKeyboardType
        private var font: UIFont
        private var foregroundColor: UIColor?
        private var contentType: UITextContentType?
        private var autocorrection: UITextAutocorrectionType = .default
        private var autocapitalization: UITextAutocapitalizationType = .sentences
        private var isSecure: Bool = false
        private var isUserInteractionEnabled: Bool = true
        @Binding private var focused: Bool

        init(text: Binding<String>,
             focused: Binding<Bool>,
             returnKeyType: UIReturnKeyType,
             keyboardType: UIKeyboardType,
             font: UIFont,
             foregroundColor: UIColor?,
             contentType: UITextContentType?,
             autocorrection: UITextAutocorrectionType,
             autocapitalization: UITextAutocapitalizationType,
             isSecure: Bool,
             isUserInteractionEnabled: Bool,
             onEditingChanged: @escaping (Bool) -> Void,
             onCommit: @escaping () -> Void)
        {
            _text = text
            _focused = focused
            self.returnKeyType = returnKeyType
            self.keyboardType = keyboardType
            self.font = font
            self.foregroundColor = foregroundColor
            self.contentType = contentType
            self.autocorrection = autocorrection
            self.autocapitalization = autocapitalization
            self.isSecure = isSecure
            self.isUserInteractionEnabled = isUserInteractionEnabled
            self.onEditingChanged = onEditingChanged
            self.onCommit = onCommit
        }

        func makeUIView(context: Context) -> UITextField {
            let view = UITextField()
            view.delegate = context.coordinator
            view.backgroundColor = .clear
            view.returnKeyType = returnKeyType
            view.keyboardType = keyboardType
            view.font = font
            view.textColor = foregroundColor
            view.textContentType = contentType
            view.autocorrectionType = autocorrection
            view.autocapitalizationType = autocapitalization
            view.isSecureTextEntry = isSecure
            view.clearButtonMode = .never

            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            return view
        }

        func updateUIView(_ uiView: UITextField, context: Context) {
            uiView.isUserInteractionEnabled = isUserInteractionEnabled
            uiView.textColor = foregroundColor
            uiView.returnKeyType = returnKeyType
            uiView.keyboardType = keyboardType
            uiView.font = font
            uiView.textContentType = contentType
            uiView.autocorrectionType = autocorrection
            uiView.autocapitalizationType = autocapitalization
            uiView.isSecureTextEntry = isSecure
            uiView.clearButtonMode = .never
            
//            if uiView.text != text {
//                uiView.text = text
//            }

            // toggling isUserInteractionEnabled and focusing on the same run-loop doesn't work so we bump this to next rl
            DispatchQueue.main.async {
                if focused {
                    uiView.becomeFirstResponder()
                } else {
                    uiView.resignFirstResponder()
                }
            }
        }

        func makeCoordinator() -> Coordinator {
            return Coordinator(
                focused: $focused,
                onChanged: onEditingChanged,
                onDone: onCommit
            )
        }

        final class Coordinator: NSObject, UITextFieldDelegate {
            @Binding var focused: Bool
            var onChanged: (Bool) -> Void
            var onDone: () -> Void

            init(
                focused: Binding<Bool>,
                onChanged: @escaping (Bool) -> Void,
                onDone: @escaping () -> Void
            ) {
                self.onChanged = onChanged
                self.onDone = onDone
                self._focused = focused
            }

            func textField(_: UITextField, shouldChangeCharactersIn _: NSRange, replacementString _: String) -> Bool {
                return true
            }

            func textFieldDidEndEditing(_: UITextField) {
                onDone()
                focused = false
            }

            func textFieldDidBeginEditing(_: UITextField) {
                onChanged(false)
                focused = true
            }
        }
    }

    #if DEBUG
        struct TextFieldPreview: View {
            @State private var text = ""
            @State private var isEditing: Bool = true
            @State private var focused: Bool = false

            var body: some View {
                VStack {
                    Button("Toggle Focus") {
                        focused.toggle()
                    }

                    Text("\(focused.description)")

                    LegacyTextField(text: $text)
                        .focused($focused)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white)
                        )
                        .padding(.horizontal)
                        .accentColor(.blue)
                        .colorScheme(.light)
                }
            }
        }

        #Preview {
            Color.gray
                .edgesIgnoringSafeArea(.all)
                .overlay(
                    TextFieldPreview()
                )
        }
    #endif
#endif
