//
//  PostHogTagViewModifier.swift
//  PostHog
//
//  Created by Yiannis Josephides on 19/12/2024.
//

// Inspired from: https://github.com/siteline/swiftui-introspect

#if os(iOS) && canImport(SwiftUI)
    import SwiftUI

    typealias PostHogTagViewHandler = ([UIView]) -> Void
    typealias PostHogTagLayerHandler = ([CALayer]) -> Void

    /**
     This is a helper view modifier for retrieving a list of underlying UIKit views for the current SwiftUI view.

     This implementation injects two hidden views into the SwiftUI view hierarchy, with the purpose of using them to retrieve the generated UIKit views for this SwiftUI view.

     The two injected views basically sandwich the current SwiftUI view:
        - The first view is an anchor view, which defines how far **down** we need to traverse the view hierarchy (added as a background view).
        - The second view is a tagger view, which defines how far **up** we traverse the view hierarchy (added as an overlay view).
        - Any view in between the two should be the generated UIKit views that correspond to the current View

     ```
      View Hierarchy Tree:

                       UIHostingController
                              │
                              ▼
                        _UIHostingView (Common ancestor)
                              │
                       ┌──────┴──────┐
                       ▼             ▼
                 UnrelatedView       |
                                     │
                               PostHogTagView
                                 (overlay)
                                     │
                                     ▼
                             _UIGeneratedView (e.g generated views in an HStack)
                                     │
                                     ▼
                             _UIGeneratedView (e.g generated views in an HStack)
                                     │
                                     ▼
                            PostHogTagAnchorView
                                (background)

        The general approach is:

        1. PostHogTagAnchorView injected as background (bottom boundary)
        2. PostHogTagView injected as overlay (top boundary)
        3. System renders SwiftUI view hierarchy in UIKit
        4. Find the common ancestor of the PostHogTagAnchorView and PostHogTagView (e.g _UIHostingView)
        5. Retrieve all of the descendants of common ancestor that are between PostHogTagView and PostHogTagAnchorView (excluding tagged views)

        This logic is implemented in the `getTargetViews` function, which is called from PostHogTagView.

      ```
     */
    struct PostHogTagViewModifier: ViewModifier {
        private let id = UUID()

        let onChange: PostHogTagViewHandler
        let onRemove: PostHogTagViewHandler
        let onLayerChange: PostHogTagLayerHandler?
        let onLayerRemove: PostHogTagLayerHandler?

        /**
         This is a helper view modifier for retrieving a list of underlying UIKit views for the current SwiftUI view.

         If, for example, this modifier is applied on an instance of an HStack, the returned list will contain the underlying UIKit views embedded in the HStack.
         For single views, the returned list will contain a single element, the view itself.

         On iOS 26+, SwiftUI primitives may be rendered as CALayers instead of UIViews. The layer handlers
         are called with sibling CALayers that intersect with the modified view's frame.

         - Parameters:
         - onChange: called when the underlying UIKit views are detected, or when they are layed out.
         - onRemove: called when the underlying UIKit views are removed from the view hierarchy, for cleanup.
         - onLayerChange: called when sibling CALayers are detected (iOS 26+).
         - onLayerRemove: called when sibling CALayers are removed (iOS 26+).
         */
        init(
            onChange: @escaping PostHogTagViewHandler,
            onRemove: @escaping PostHogTagViewHandler,
            onLayerChange: PostHogTagLayerHandler? = nil,
            onLayerRemove: PostHogTagLayerHandler? = nil
        ) {
            self.onChange = onChange
            self.onRemove = onRemove
            self.onLayerChange = onLayerChange
            self.onLayerRemove = onLayerRemove
        }

        func body(content: Content) -> some View {
            content
                .background(
                    PostHogTagAnchorView(id: id)
                        .accessibility(hidden: true)
                        .frame(width: 0, height: 0)
                )
                .overlay(
                    PostHogTagView(
                        id: id,
                        onChange: onChange,
                        onRemove: onRemove,
                        onLayerChange: onLayerChange,
                        onLayerRemove: onLayerRemove
                    )
                    .accessibility(hidden: true)
                    .frame(width: 0, height: 0)
                )
        }
    }

    struct PostHogTagView: UIViewRepresentable {
        final class Coordinator {
            var onChangeHandler: PostHogTagViewHandler?
            var onRemoveHandler: PostHogTagViewHandler?
            var onLayerChangeHandler: PostHogTagLayerHandler?
            var onLayerRemoveHandler: PostHogTagLayerHandler?

            private var _targets: [Weak<UIView>]
            var cachedTargets: [UIView] {
                get { _targets.compactMap(\.value) }
                set { _targets = newValue.map(Weak.init) }
            }

            private var _layerTargets: [Weak<CALayer>]
            var cachedLayerTargets: [CALayer] {
                get { _layerTargets.compactMap(\.value) }
                set { _layerTargets = newValue.map(Weak.init) }
            }

            init(
                onRemove: PostHogTagViewHandler?,
                onLayerRemove: PostHogTagLayerHandler?
            ) {
                _targets = []
                _layerTargets = []
                onRemoveHandler = onRemove
                onLayerRemoveHandler = onLayerRemove
            }
        }

        @Binding
        private var observed: Void // workaround for state changes not triggering view updates
        private let id: UUID
        private let onChangeHandler: PostHogTagViewHandler?
        private let onRemoveHandler: PostHogTagViewHandler?
        private let onLayerChangeHandler: PostHogTagLayerHandler?
        private let onLayerRemoveHandler: PostHogTagLayerHandler?

        init(
            id: UUID,
            onChange: PostHogTagViewHandler?,
            onRemove: PostHogTagViewHandler?,
            onLayerChange: PostHogTagLayerHandler? = nil,
            onLayerRemove: PostHogTagLayerHandler? = nil
        ) {
            _observed = .constant(())
            self.id = id
            onChangeHandler = onChange
            onRemoveHandler = onRemove
            onLayerChangeHandler = onLayerChange
            onLayerRemoveHandler = onLayerRemove
        }

        func makeCoordinator() -> Coordinator {
            // dismantleUIView is Static, so we need to store the onRemoveHandler
            // somewhere where we can access it during view distruction
            Coordinator(onRemove: onRemoveHandler, onLayerRemove: onLayerRemoveHandler)
        }

        func makeUIView(context: Context) -> PostHogTagUIView {
            let view = PostHogTagUIView(id: id) { controller in
                let targets = getTargetViews(from: controller)
                if !targets.isEmpty {
                    context.coordinator.cachedTargets = targets
                    onChangeHandler?(targets)
                }

                // On iOS 26+, also find sibling layers that intersect with the view's frame
                if #available(iOS 26.0, *), let layerHandler = onLayerChangeHandler {
                    let layers = getTargetLayers(from: controller)
                    if !layers.isEmpty {
                        context.coordinator.cachedLayerTargets = layers
                        layerHandler(layers)
                    }
                }
            }

            return view
        }

        func updateUIView(_: PostHogTagUIView, context _: Context) {
            //
        }

        static func dismantleUIView(_ uiView: PostHogTagUIView, coordinator: Coordinator) {
            // using cached targets should be good here
            let targets = coordinator.cachedTargets.isEmpty
                ? getTargetViews(from: uiView)
                : coordinator.cachedTargets

            if !targets.isEmpty {
                coordinator.onRemoveHandler?(targets)
            }

            // Clean up layer targets on iOS 26+
            if #available(iOS 26.0, *) {
                let layerTargets = coordinator.cachedLayerTargets.isEmpty
                    ? getTargetLayers(from: uiView)
                    : coordinator.cachedLayerTargets

                if !layerTargets.isEmpty {
                    coordinator.onLayerRemoveHandler?(layerTargets)
                }
            }

            uiView.postHogTagView = nil
            uiView.handler = nil
        }
    }

    private let swiftUIIgnoreTypes: [AnyClass] = [
        // .clipShape or .clipped SwiftUI modifiers will add this to view hierarchy
        // Not sure of its functionality, but it seems to be just a wrapper view with no visual impact
        //
        // We can safely ignore from list of descendant views, since it's sometimes being tagged
        // for replay masking unintentionally
        "SwiftUI._UIInheritedView",
    ].compactMap(NSClassFromString)

    func getTargetViews(from taggerView: UIView) -> [UIView] {
        guard
            let anchorView = taggerView.postHogAnchor,
            let commonAncestor = anchorView.nearestCommonAncestor(with: taggerView)
        else {
            return []
        }

        return commonAncestor
            .allDescendants(between: anchorView, and: taggerView)
            .lazy
            .filter {
                // ignore some system SwiftUI views
                !swiftUIIgnoreTypes.contains(where: $0.isKind(of:))
            }
            .filter {
                // exclude injected views
                !$0.postHogView
            }
    }

    /// On iOS 26+, SwiftUI primitives may be rendered as CALayers instead of UIViews.
    /// This function finds sibling CALayers that are rendered alongside the modified view.
    ///
    /// On iOS 26, when `.postHogMask()` is applied to a SwiftUI view like `CustomView()`,
    /// the content (Image, Text) is rendered as CALayers, and the anchor/tagger views are
    /// added as sibling UIViews wrapped in `UIKitPlatformViewHost`. The parent view's layer
    /// contains both the content layers and the wrapper view layers.
    @available(iOS 26.0, *)
    func getTargetLayers(from taggerView: UIView) -> [CALayer] {
        // taggerView is PostHogTagUIView
        // -> superview is UIKitPlatformViewHost wrapper
        // -> superview is the parent view containing both wrapper and content layers
        guard let parentView = taggerView.superview?.superview else {
            return []
        }

        // Find all sublayers of the parent view's layer that are not backed by UIViews
        // These are the SwiftUI content layers (Text, Image, SF Symbols, etc.)
        var contentLayers: [CALayer] = []
        collectContentLayers(from: parentView.layer, results: &contentLayers)

        return contentLayers
    }

    /// Collect all sublayers that are not backed by UIViews (i.e., SwiftUI content layers)
    @available(iOS 26.0, *)
    private func collectContentLayers(from layer: CALayer, results: inout [CALayer]) {
        for sublayer in layer.sublayers ?? [] {
            // Skip layers that belong to views
            if sublayer.delegate is UIView {
                continue
            }

            // Skip zero-size layers
            guard sublayer.bounds.size.width > 0 && sublayer.bounds.size.height > 0 else {
                continue
            }

            results.append(sublayer)

            // Recursively collect from sublayers
            collectContentLayers(from: sublayer, results: &results)
        }
    }

    private struct PostHogTagAnchorView: UIViewRepresentable {
        var id: UUID

        func makeUIView(context _: Context) -> some UIView {
            PostHogTagAnchorUIView(id: id)
        }

        func updateUIView(_: UIViewType, context _: Context) {
            //
        }
    }

    private class PostHogTagAnchorUIView: UIView {
        let id: UUID

        init(id: UUID) {
            self.id = id
            super.init(frame: .zero)
            TaggingStore.shared[id, default: .init()].anchor = self
            postHogView = true
        }

        required init?(coder _: NSCoder) {
            id = UUID()
            super.init(frame: .zero)
        }
    }

    final class PostHogTagUIView: UIView {
        let id: UUID
        var handler: (() -> Void)?

        init(
            id: UUID,
            handler: ((PostHogTagUIView) -> Void)?
        ) {
            self.id = id
            super.init(frame: .zero)
            self.handler = { [weak self] in
                guard let self else {
                    return
                }
                handler?(self)
            }

            TaggingStore.shared[id, default: .init()].tagger = self
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            id = UUID()
            super.init(frame: .zero)
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            postHogTagView = self
            postHogView = true
            handler?()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            handler?()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            handler?()
        }
    }

    private extension UIView {
        var postHogTagView: PostHogTagUIView? {
            get { objc_getAssociatedObject(self, &AssociatedKeys.phTagView) as? PostHogTagUIView }
            set { objc_setAssociatedObject(self, &AssociatedKeys.phTagView, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        }

        var postHogView: Bool {
            get { objc_getAssociatedObject(self, &AssociatedKeys.phView) as? Bool ?? false }
            set { objc_setAssociatedObject(self, &AssociatedKeys.phView, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        }

        func allDescendants(between bottomEntity: UIView, and topEntity: UIView) -> some Sequence<UIView> {
            descendants
                .lazy
                .drop(while: { $0 !== bottomEntity })
                .prefix(while: { $0 !== topEntity })
        }

        var ancestors: some Sequence<UIView> {
            sequence(first: self, next: { $0.superview }).dropFirst()
        }

        var descendants: some Sequence<UIView> {
            recursiveSequence([self], children: { $0.subviews }).dropFirst()
        }

        func isDescendant(of other: UIView) -> Bool {
            ancestors.contains(other)
        }

        func nearestCommonAncestor(with other: UIView) -> UIView? {
            var nearestAncestor: UIView? = self

            while let currentEntity = nearestAncestor, !other.isDescendant(of: currentEntity) {
                nearestAncestor = currentEntity.superview
            }

            return nearestAncestor
        }

        var postHogAnchor: UIView? {
            if let tagView = postHogTagView {
                return TaggingStore.shared[tagView.id]?.anchor
            }
            return nil
        }
    }

    /**
     A helper store for storing reference pairs between anchor and tagger views
     */
    @MainActor private enum TaggingStore {
        static var shared: [UUID: Pair] = [:]

        struct Pair {
            weak var anchor: PostHogTagAnchorUIView?
            weak var tagger: PostHogTagUIView?
        }
    }

    /**
     Recursively iterates over a sequence of elements, applying a function to each element to get its children.

     - Parameters:
     - sequence: The sequence of elements to iterate over.
     - children: A function that takes an element and returns a sequence of its children.
     - Returns: An AnySequence that iterates over all elements and their children.
     */
    private func recursiveSequence<S: Sequence>(_ sequence: S, children: @escaping (S.Element) -> S) -> AnySequence<S.Element> {
        AnySequence {
            var mainIterator = sequence.makeIterator()
            // Current iterator, or `nil` if all sequences are exhausted:
            var iterator: AnyIterator<S.Element>?

            return AnyIterator {
                guard let iterator, let element = iterator.next() else {
                    if let element = mainIterator.next() {
                        iterator = recursiveSequence(children(element), children: children).makeIterator()
                        return element
                    }
                    return nil
                }
                return element
            }
        }
    }

    /**
     Boxing a weak reference to a reference type.
     */
    final class Weak<T: AnyObject> {
        weak var value: T?

        init(_ wrappedValue: T? = nil) {
            value = wrappedValue
        }
    }

#endif
