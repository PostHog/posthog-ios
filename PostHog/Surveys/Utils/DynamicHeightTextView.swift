//
//  DynamicHeightTextView.swift
//  PostHog
//
//  Created by Ioannis Josephides on 10/03/2025.
//

#if os(iOS)
    import SwiftUI
    import UIKit

    /**
     Note: `TextEditor` was introduced in iOS14+
     Since we want to support iOS13+, we have to roll out our own
     */
    struct DynamicHeightTextView: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.layoutDirection) private var layoutDirection

        @Binding var text: String
        var onEditingChanged: (Bool) -> Void = { _ in }
        var onCommit: () -> Void = {}

        private var font: UIFont = .preferredFont(forTextStyle: .body)
        private var foregroundColor: UIColor?
        private var textAlignment: NSTextAlignment?
        private var clearsOnInsertion: Bool = false
        private var contentType: UITextContentType?
        private var returnKeyType: UIReturnKeyType = .default
        private var keyboardType: UIKeyboardType = .default
        private var autocorrection: UITextAutocorrectionType = .no
        private var autocapitalization: UITextAutocapitalizationType = .sentences
        private var lineLimit: Int?
        private var truncationMode: NSLineBreakMode?
        private var isSecure: Bool = false
        private var isEditable: Bool = true
        private var isSelectable: Bool = true
        private var isScrollingEnabled: Bool = false
        private var placeholderText: Text?
        private var minHeight: CGFloat?

        @State private var dynamicHeight: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize

        init(text: Binding<String>,
             placeholder: Text? = nil,
             onEditingChanged: @escaping (Bool) -> Void = { _ in },
             onCommit: @escaping () -> Void = {})
        {
            _text = text
            placeholderText = placeholder
            self.onEditingChanged = onEditingChanged
            self.onCommit = onCommit
        }

        var body: some View {
            UITextViewWrapper(
                text: $text,
                calculatedHeight: $dynamicHeight,
                returnKeyType: returnKeyType,
                keyboardType: keyboardType,
                font: font,
                foregroundColor: foregroundColor,
                textAlignment: textAlignment ?? defaultTextAlignment,
                clearsOnInsertion: clearsOnInsertion,
                contentType: contentType,
                autocorrection: autocorrection,
                autocapitalization: autocapitalization,
                lineLimit: lineLimit,
                truncationMode: truncationMode,
                isSecure: isSecure,
                isEditable: isEditable,
                isSelectable: isSelectable,
                isScrollingEnabled: isScrollingEnabled,
                isUserInteractionEnabled: isEnabled,
                onEditingChanged: onEditingChanged,
                onCommit: onCommit
            )
            .frame(
                minHeight: minHeight ?? dynamicHeight,
                maxHeight: dynamicHeight
            )
            .overlay(placeholderView, alignment: .topLeading)
        }

        @ViewBuilder
        private var placeholderView: some View {
            if text.isEmpty {
                placeholderText
            }
        }

        private var defaultTextAlignment: NSTextAlignment {
            layoutDirection == .leftToRight ? .left : .right
        }
    }

    extension DynamicHeightTextView {
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

        func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
            var view = self
            switch alignment {
            case .leading:
                view.textAlignment = layoutDirection ~= .leftToRight ? .left : .right
            case .trailing:
                view.textAlignment = layoutDirection ~= .leftToRight ? .right : .left
            case .center:
                view.textAlignment = .center
            }
            return view
        }

        func clearOnInsertion(_ value: Bool) -> some View {
            var view = self
            view.clearsOnInsertion = value
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

        func isEditable(_ isEditable: Bool) -> some View {
            var view = self
            view.isEditable = isEditable
            return view
        }

        func isSelectable(_ isSelectable: Bool) -> Self {
            var view = self
            view.isSelectable = isSelectable
            return view
        }

        func enableScrolling(_ isScrollingEnabled: Bool) -> Self {
            var view = self
            view.isScrollingEnabled = isScrollingEnabled
            return view
        }

        func keyboardType(_ type: UIKeyboardType) -> Self {
            var view = self
            view.keyboardType = type
            return view
        }

        func returnKey(_ style: UIReturnKeyType) -> Self {
            var view = self
            view.returnKeyType = style
            return view
        }

        func lineLimit(_ number: Int?) -> Self {
            var view = self
            view.lineLimit = number
            return view
        }

        func truncationMode(_ mode: Text.TruncationMode) -> Self {
            var view = self
            switch mode {
            case .head: view.truncationMode = .byTruncatingHead
            case .tail: view.truncationMode = .byTruncatingTail
            case .middle: view.truncationMode = .byTruncatingMiddle
            @unknown default:
                fatalError("Unknown text truncation mode")
            }
            return view
        }

        func minHeight(_ value: CGFloat) -> Self {
            var view = self
            view.minHeight = value
            return view
        }

        func placeholder(_ text: Text) -> Self {
            var view = self
            view.placeholderText = text
            return view
        }
    }

    fileprivate struct UITextViewWrapper: UIViewRepresentable {
        @Binding var text: String
        @Binding var calculatedHeight: CGFloat

        var onEditingChanged: (Bool) -> Void = { _ in }
        var onCommit: () -> Void = {}

        private var returnKeyType: UIReturnKeyType
        private var keyboardType: UIKeyboardType
        private var font: UIFont
        private var foregroundColor: UIColor?
        private var textAlignment: NSTextAlignment
        private var clearsOnInsertion: Bool = false
        private var contentType: UITextContentType?
        private var autocorrection: UITextAutocorrectionType
        private var autocapitalization: UITextAutocapitalizationType
        private var lineLimit: Int?
        private var truncationMode: NSLineBreakMode?
        private var isSecure: Bool = false
        private var isEditable: Bool = true
        private var isSelectable: Bool = true
        private var isScrollingEnabled: Bool = false
        private var isUserInteractionEnabled: Bool = true

        init(text: Binding<String>,
             calculatedHeight: Binding<CGFloat>,
             returnKeyType: UIReturnKeyType,
             keyboardType: UIKeyboardType,
             font: UIFont,
             foregroundColor: UIColor?,
             textAlignment: NSTextAlignment,
             clearsOnInsertion: Bool,
             contentType: UITextContentType?,
             autocorrection: UITextAutocorrectionType,
             autocapitalization: UITextAutocapitalizationType,
             lineLimit: Int?,
             truncationMode: NSLineBreakMode?,
             isSecure: Bool,
             isEditable: Bool,
             isSelectable: Bool,
             isScrollingEnabled: Bool,
             isUserInteractionEnabled: Bool,
             onEditingChanged: @escaping (Bool) -> Void,
             onCommit: @escaping () -> Void)
        {
            _text = text
            _calculatedHeight = calculatedHeight
            self.returnKeyType = returnKeyType
            self.keyboardType = keyboardType
            self.font = font
            self.foregroundColor = foregroundColor
            self.textAlignment = textAlignment
            self.clearsOnInsertion = clearsOnInsertion
            self.contentType = contentType
            self.autocorrection = autocorrection
            self.autocapitalization = autocapitalization
            self.lineLimit = lineLimit
            self.truncationMode = truncationMode
            self.isSecure = isSecure
            self.isEditable = isEditable
            self.isSelectable = isSelectable
            self.isScrollingEnabled = isScrollingEnabled
            self.isUserInteractionEnabled = isUserInteractionEnabled
            self.onEditingChanged = onEditingChanged
            self.onCommit = onCommit
        }

        func makeUIView(context: Context) -> UITextView {
            let view = UITextView()
            view.delegate = context.coordinator
            view.backgroundColor = .clear

            view.textContainerInset = UIEdgeInsets.zero
            view.textContainer.lineFragmentPadding = 0
            view.returnKeyType = returnKeyType
            view.keyboardType = keyboardType
            view.font = font
            view.textColor = foregroundColor
            view.textAlignment = textAlignment
            view.clearsOnInsertion = clearsOnInsertion
            view.textContentType = contentType
            view.autocorrectionType = autocorrection
            view.autocapitalizationType = autocapitalization
            view.isSecureTextEntry = isSecure
            view.isEditable = isEditable
            view.isSelectable = isSelectable
            view.isScrollEnabled = isScrollingEnabled
            view.isUserInteractionEnabled = isUserInteractionEnabled

            if let lineLimit = lineLimit {
                view.textContainer.maximumNumberOfLines = lineLimit
            }
            if let truncationMode = truncationMode {
                view.textContainer.lineBreakMode = truncationMode
            }

            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return view
        }

        func updateUIView(_ uiView: UITextView, context _: Context) {
            updateText(uiView, text: text)
            uiView.returnKeyType = returnKeyType
            uiView.keyboardType = keyboardType
            uiView.font = font
            uiView.textColor = foregroundColor
            uiView.textAlignment = textAlignment
            uiView.clearsOnInsertion = clearsOnInsertion
            uiView.textContentType = contentType
            uiView.autocorrectionType = autocorrection
            uiView.autocapitalizationType = autocapitalization
            uiView.isSecureTextEntry = isSecure
            uiView.isEditable = isEditable
            uiView.isSelectable = isSelectable
            uiView.isScrollEnabled = isScrollingEnabled
            uiView.isUserInteractionEnabled = isUserInteractionEnabled

            if let lineLimit = lineLimit {
                uiView.textContainer.maximumNumberOfLines = lineLimit
            }
            if let truncationMode = truncationMode {
                uiView.textContainer.lineBreakMode = truncationMode
            }
            
            if uiView.text != text {
                uiView.text = text
            }

            UITextViewWrapper.recalculateHeight(view: uiView, result: $calculatedHeight)
        }
        
        private func updateText(_ textView: UITextView, text: String) {
            if let selectedRange = textView.selectedTextRange {
                let cursorOffset = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
                textView.text = text
                if let newPosition = textView.position(from: textView.beginningOfDocument, offset: cursorOffset) {
                    textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
                }
            } else {
                textView.text = text
            }
        }

        func makeCoordinator() -> Coordinator {
            return Coordinator(text: $text, calculatedHeight: $calculatedHeight, onChanged: onEditingChanged, onDone: onCommit)
        }

        fileprivate static func recalculateHeight(view: UIView, result: Binding<CGFloat>) {
            let maxHeightSize = CGSize(width: view.frame.size.width, height: CGFloat.greatestFiniteMagnitude)
            let newSize = view.sizeThatFits(maxHeightSize)
            if result.wrappedValue != newSize.height {
                DispatchQueue.main.async {
                    // must be called asynchronously
                    result.wrappedValue = newSize.height
                }
            }
        }

        final class Coordinator: NSObject, UITextViewDelegate {
            @Binding var text: String
            @Binding var calculatedHeight: CGFloat
            var onChanged: (Bool) -> Void
            var onDone: () -> Void

            init(text: Binding<String>, calculatedHeight: Binding<CGFloat>, onChanged: @escaping (Bool) -> Void, onDone: @escaping () -> Void) {
                _text = text
                _calculatedHeight = calculatedHeight
                self.onChanged = onChanged
                self.onDone = onDone
            }

            func textViewDidChange(_ uiView: UITextView) {
                text = uiView.text
                onChanged(true)
                UITextViewWrapper.recalculateHeight(view: uiView, result: $calculatedHeight)
            }

            func textViewDidBeginEditing(_: UITextView) {
                onChanged(false)
            }

            func textViewDidEndEditing(_: UITextView) {
                onDone()
            }
        }
    }

    #if DEBUG
        struct TextViewPreview: View {
            @State private var text = ""
            @State private var isEditing: Bool = true

            var body: some View {
                DynamicHeightTextView(text: $text)
                    .minHeight(100)
                    .placeholder(
                        Text("Start typing...")
                            .foregroundColor(.secondary)
                    )
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

        #Preview {
            VStack {
                Text("Stacked view")
                TextViewPreview()
                Text("Stacked view")
                Spacer()
            }
            .background(Color.gray)
        }
    #endif
#endif
