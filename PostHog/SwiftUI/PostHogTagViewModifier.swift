//
//  PostHogTagViewModifier.swift
//  PostHog
//
//  Created by Yiannis Josephides on 19/12/2024.
//

// Inspired from: https://github.com/siteline/swiftui-introspect

#if os(iOS) && canImport(SwiftUI)
    import SwiftUI

    /// - owner: identity of the injected view that resolved these targets. Used for
    ///   ref-counted flag ownership (see `PostHogFlagOwners`), so that overlapping
    ///   masks cannot clear each other's targets on teardown.
    typealias PostHogTagHandler = (_ owner: ObjectIdentifier, _ views: [UIView], _ layers: [CALayer]) -> Void

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

     ### iOS 26
     On iOS 26, SwiftUI primitives (Text, Image, Button) may be rendered as CALayers
     instead of UIViews. An additional `PostHogFrameCaptureView` overlay detects these layers via
     `getTargetLayers` by walking up from the capture view to find a container with
     non-UIView-backed sublayers, then collects all CALayers within the reference frame of the original view.

     ```
      iOS 26 View/Layer Hierarchy:

                        _UIHostingView
                              │
               ┌──────────────┼──────────────┐
               ▼              ▼              ▼
         [CALayer]      _UIInheritedView   PostHogTagView
       CGDrawingLayer        │               (overlay)
       (Text/Image)          ▼
                      UIKitPlatformViewHost
                              │
                              ▼
                    PostHogFrameCaptureUIView
     ```
     */
    struct PostHogTagViewModifier: ViewModifier {
        private let id = UUID()

        let onChange: PostHogTagHandler
        let onRemove: PostHogTagHandler

        /**
         This is a helper view modifier for retrieving a list of underlying UIKit views for the current SwiftUI view.

         If, for example, this modifier is applied on an instance of an HStack, the returned list will contain the underlying UIKit views embedded in the HStack.
         For single views, the returned list will contain a single element, the view itself.

         On iOS 26+, SwiftUI primitives may be rendered as CALayers instead of UIViews.
         The layers array will be populated on iOS 26+, empty on earlier versions.

         - Parameters:
         - onChange: called when the underlying UIKit views/layers are detected, or when they are layed out.
         - onRemove: called when the underlying UIKit views/layers are removed from the view hierarchy, for cleanup.
         */
        init(
            onChange: @escaping PostHogTagHandler,
            onRemove: @escaping PostHogTagHandler
        ) {
            self.onChange = onChange
            self.onRemove = onRemove
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
                        onRemove: onRemove
                    )
                    .accessibility(hidden: true)
                    .frame(width: 0, height: 0)
                )
                .modifier(PostHogFrameCaptureModifier(
                    id: id,
                    onChange: onChange,
                    onRemove: onRemove
                ))
        }
    }

    // MARK: - iOS 26+ Layer Detection

    /// A view modifier that adds a full-sized overlay for iOS 26+ layer detection.
    /// This overlay view is used to find CALayers that are contained within its frame.
    private struct PostHogFrameCaptureModifier: ViewModifier {
        let id: UUID
        let onChange: PostHogTagHandler
        let onRemove: PostHogTagHandler

        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.overlay(
                    PostHogFrameCaptureView(
                        id: id,
                        onChange: onChange,
                        onRemove: onRemove
                    )
                    .allowsHitTesting(false)
                    .accessibility(hidden: true)
                )
            } else {
                content
            }
        }
    }

    /// A full-sized UIViewRepresentable for iOS 26+ that detects CALayers within its frame.
    @available(iOS 26.0, *)
    private struct PostHogFrameCaptureView: UIViewRepresentable {
        let id: UUID
        let onChange: PostHogTagHandler
        let onRemove: PostHogTagHandler

        func makeCoordinator() -> Coordinator {
            Coordinator(onRemove: onRemove)
        }

        func makeUIView(context: Context) -> PostHogFrameCaptureUIView {
            let coordinator = context.coordinator
            let changeHandler = onChange
            let view = PostHogFrameCaptureUIView(id: id) { captureView in
                let layers = getTargetLayers(from: captureView)
                guard !layers.isEmpty else { return }

                // Reconcile against the previous resolution: release ownership on
                // layers that dropped out, otherwise recycled layers keep stale flags.
                let owner = ObjectIdentifier(captureView)
                let previous = coordinator.cachedLayers
                let dropped = previous.filter { previousLayer in
                    !layers.contains(where: { $0 === previousLayer })
                }
                if !dropped.isEmpty {
                    coordinator.onRemoveHandler(owner, [], dropped)
                }

                coordinator.cachedLayers = layers
                changeHandler(owner, [], layers)
            }
            view.postHogView = true
            return view
        }

        func updateUIView(_ uiView: PostHogFrameCaptureUIView, context _: Context) {
            uiView.postHogView = true
            uiView.superview?.postHogView = true
            // Trigger layer detection on layout updates
            uiView.detectLayers()
        }

        static func dismantleUIView(_ uiView: PostHogFrameCaptureUIView, coordinator: Coordinator) {
            let layers = coordinator.cachedLayers.isEmpty
                ? getTargetLayers(from: uiView)
                : coordinator.cachedLayers

            if !layers.isEmpty {
                coordinator.onRemoveHandler(ObjectIdentifier(uiView), [], layers)
            }
            uiView.handler = nil
        }

        final class Coordinator {
            let onRemoveHandler: PostHogTagHandler
            private var _cachedLayers: [Weak<CALayer>] = []

            var cachedLayers: [CALayer] {
                get { _cachedLayers.compactMap(\.value) }
                set { _cachedLayers = newValue.map(Weak.init) }
            }

            init(onRemove: @escaping PostHogTagHandler) {
                onRemoveHandler = onRemove
            }
        }
    }

    @available(iOS 26.0, *)
    private class PostHogFrameCaptureUIView: UIView {
        let id: UUID
        var handler: (() -> Void)?

        init(id: UUID, handler: ((PostHogFrameCaptureUIView) -> Void)?) {
            self.id = id
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            postHogView = true
            self.handler = { [weak self] in
                guard let self else { return }
                handler?(self)
            }
        }

        required init?(coder: NSCoder) {
            id = UUID()
            super.init(coder: coder)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Per-layout re-scans are coalesced: one drain per run-loop turn instead
            // of a full layer-tree walk per capture view per layout pass.
            PostHogTagResolutionCoalescer.markDirty(self)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Trigger detection when fully added to window hierarchy. Synchronous on
            // first attach so freshly realized content is flagged before capture.
            if window != nil {
                detectLayers()
            }
        }

        func detectLayers() {
            // Only detect if we're fully in the view hierarchy
            guard superview?.superview != nil else { return }
            handler?()
        }
    }

    struct PostHogTagView: UIViewRepresentable {
        final class Coordinator {
            let onRemoveHandler: PostHogTagHandler

            private var _targets: [Weak<UIView>]
            var cachedTargets: [UIView] {
                get { _targets.compactMap(\.value) }
                set { _targets = newValue.map(Weak.init) }
            }

            init(onRemove: @escaping PostHogTagHandler) {
                _targets = []
                onRemoveHandler = onRemove
            }
        }

        @Binding
        private var observed: Void // workaround for state changes not triggering view updates
        private let id: UUID
        private let onChangeHandler: PostHogTagHandler
        private let onRemoveHandler: PostHogTagHandler

        init(
            id: UUID,
            onChange: @escaping PostHogTagHandler,
            onRemove: @escaping PostHogTagHandler
        ) {
            _observed = .constant(())
            self.id = id
            onChangeHandler = onChange
            onRemoveHandler = onRemove
        }

        func makeCoordinator() -> Coordinator {
            // dismantleUIView is Static, so we need to store the onRemoveHandler
            // somewhere where we can access it during view distruction
            Coordinator(onRemove: onRemoveHandler)
        }

        func makeUIView(context: Context) -> PostHogTagUIView {
            let coordinator = context.coordinator
            let onChange = onChangeHandler
            return PostHogTagUIView(id: id) { taggerView in
                resolveTagTargets(from: taggerView, coordinator: coordinator, onChange: onChange)
            }
        }

        func updateUIView(_ uiView: PostHogTagUIView, context _: Context) {
            markPostHogView(uiView)
        }

        static func dismantleUIView(_ uiView: PostHogTagUIView, coordinator: Coordinator) {
            // using cached targets should be good here
            let targets = coordinator.cachedTargets.isEmpty
                ? getTargetViews(from: uiView)
                : coordinator.cachedTargets

            if !targets.isEmpty {
                coordinator.onRemoveHandler(ObjectIdentifier(uiView), targets, [])
            }

            uiView.postHogTagView = nil
            uiView.handler = nil
        }
    }

    /// Resolves the tagger's current targets, reconciles them against the previously
    /// cached set, and invokes `onChange` with the new set. The reconciliation releases
    /// flag ownership on targets that dropped out of the resolution — without it, every
    /// re-resolution (content replacement, hierarchy churn) would leak stale ownership
    /// on views SwiftUI has recycled elsewhere.
    func resolveTagTargets(
        from taggerView: PostHogTagUIView,
        coordinator: PostHogTagView.Coordinator,
        onChange: PostHogTagHandler
    ) {
        let targets = getTargetViews(from: taggerView)
        guard !targets.isEmpty else { return }

        let owner = ObjectIdentifier(taggerView)
        let previous = coordinator.cachedTargets
        let dropped = previous.filter { previousTarget in
            !targets.contains(where: { $0 === previousTarget })
        }
        if !dropped.isEmpty {
            coordinator.onRemoveHandler(owner, dropped, [])
        }

        coordinator.cachedTargets = targets
        onChange(owner, targets, [])
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
            let commonAncestor = anchorView.nearestCommonAncestor(with: taggerView),
            // The anchor is not part of its own descendants, so when the common
            // ancestor degenerates to the anchor itself the traversal never starts.
            commonAncestor !== anchorView
        else {
            return []
        }

        // Iterative pre-order DFS over the flat descendant sequence of the common
        // ancestor, starting directly at the anchor (everything before it was only
        // ever enumerated to be dropped) and terminating at the tagger. Replaces the
        // recursiveSequence/AnyIterator lazy chains whose per-element overhead
        // (closure boxes, protocol-witness dispatch, per-node subviews bridging)
        // dominated launch and scroll traces.
        //
        // Seed the stack with the anchor plus the not-yet-visited right siblings
        // along the path from the anchor up to the common ancestor — exactly the
        // remainder of the flat pre-order sequence from the anchor onwards.
        var siblingChains: [ArraySlice<UIView>] = []
        var pathNode = anchorView
        while pathNode !== commonAncestor {
            guard let parent = pathNode.superview else { return [] }
            let siblings = parent.subviews
            if let index = siblings.firstIndex(where: { $0 === pathNode }) {
                siblingChains.append(siblings[(index + 1)...])
            }
            pathNode = parent
        }

        var stack: [UIView] = []
        for chain in siblingChains.reversed() {
            stack.append(contentsOf: chain.reversed())
        }
        stack.append(anchorView)

        var targets: [UIView] = []
        while let view = stack.popLast() {
            if view === taggerView {
                break
            }
            // ignore some system SwiftUI views, and exclude injected views
            if !swiftUIIgnoreTypes.contains(where: view.isKind(of:)), !view.postHogView {
                targets.append(view)
            }
            stack.append(contentsOf: view.subviews.reversed())
        }
        return targets
    }

    /// On iOS 26+, SwiftUI primitives may be rendered as CALayers instead of UIViews.
    /// This function finds sibling CALayers that are rendered alongside the modified view.
    ///
    /// On iOS 26, when `.postHogMask()` is applied to a SwiftUI view like `CustomView()`,
    /// the content (Image, Text) is rendered as CALayers, and the anchor/tagger views are
    /// added as sibling UIViews wrapped in `UIKitPlatformViewHost`. The parent view's layer
    /// contains both the content layers and the wrapper view layers.
    @available(iOS 26.0, *)
    private func getTargetLayers(from captureView: PostHogFrameCaptureUIView) -> [CALayer] {
        // Walk up the view hierarchy to find a container view whose layer has
        // non-UIView-backed sublayers (i.e., SwiftUI content rendered as CALayers).
        //
        // On iOS 26, the structure is typically:
        //   _UIHostingView
        //     ├─ [CALayer] CGDrawingLayer (Text/Image content)
        //     └─ _UIInheritedView
        //         └─ UIKitPlatformViewHost
        //             └─ PostHogFrameCaptureUIView  <- we start here

        // Find the view that contains both content layers and our wrapper
        // by walking up until we find a view whose layer has non-view sublayers
        var currentView: UIView? = captureView.superview?.superview
        var hostingView: UIView?

        while let view = currentView {
            // Check if this view's layer has sublayers that are not backed by UIViews
            // (i.e., SwiftUI content layers like CGDrawingLayer)
            let hasContentLayers = view.layer.sublayers?.contains { sublayer in
                !(sublayer.delegate is UIView) && sublayer.bounds.size.width > 0 && sublayer.bounds.size.height > 0
            } ?? false

            if hasContentLayers {
                hostingView = view
                break
            }
            currentView = view.superview
        }

        guard let parentView = hostingView else {
            return []
        }

        // The reference frame is the masked view's own extent — the capture view is a
        // full-size overlay of the modified view. Deriving it from the hosting view
        // (the previous behavior) made every mask collect and claim content layers
        // across the entire hosting view, so overlapping masks constantly claimed and
        // released each other's layers.
        let referenceFrame = captureView.convert(captureView.bounds, to: nil)
        guard !referenceFrame.isEmpty else {
            return []
        }

        // Find all sublayers of the parent view's layer that are not backed by UIViews
        // and are contained within the reference frame
        var contentLayers: [CALayer] = []
        collectContentLayers(from: parentView.layer, containedIn: referenceFrame, results: &contentLayers)

        return contentLayers
    }

    /// Collect all sublayers that are not backed by UIViews (i.e., SwiftUI content layers)
    /// and are contained within the specified reference frame.
    @available(iOS 26.0, *)
    private func collectContentLayers(from layer: CALayer, containedIn referenceFrame: CGRect, results: inout [CALayer]) {
        for sublayer in layer.sublayers ?? [] {
            // Skip layers that belong to views
            if sublayer.delegate is UIView {
                continue
            }

            // Skip zero-size layers
            guard sublayer.bounds.size.width > 0, sublayer.bounds.size.height > 0 else {
                continue
            }

            // Get the sublayer's frame in the parent layer's coordinate space
            let sublayerFrame = sublayer.convert(sublayer.bounds, to: nil)

            // Prune clipped subtrees: when a layer clips its children to its own
            // bounds and those bounds don't reach the reference frame, nothing inside
            // it can be visible within the masked extent. Only safe under
            // masksToBounds — unclipped children may extend outside their parent.
            if sublayer.masksToBounds, !referenceFrame.intersects(sublayerFrame) {
                continue
            }

            // Only include layers whose center point is contained within the reference frame
            let sublayerFrameCenter = CGPoint(x: sublayerFrame.midX, y: sublayerFrame.midY)
            guard referenceFrame.contains(sublayerFrameCenter) else {
                // Still recurse into sublayers - they might be contained even if parent isn't
                collectContentLayers(from: sublayer, containedIn: referenceFrame, results: &results)
                continue
            }

            results.append(sublayer)

            // Recursively collect from sublayers
            collectContentLayers(from: sublayer, containedIn: referenceFrame, results: &results)
        }
    }

    private struct PostHogTagAnchorView: UIViewRepresentable {
        var id: UUID

        func makeUIView(context _: Context) -> some UIView {
            PostHogTagAnchorUIView(id: id)
        }

        func updateUIView(_ uiView: UIViewType, context _: Context) {
            markPostHogView(uiView)
        }
    }

    private func markPostHogView(_ view: UIView) {
        view.postHogView = true
        view.superview?.postHogView = true
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
        private var ancestorObserver: AncestorSubviewObserver?

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
            // First-attach resolution stays synchronous so a freshly realized view
            // (e.g. a lazy row appearing mid-scroll) is flagged before it can show
            // up in a snapshot.
            handler?()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            handler?()
            setupAncestorObserver()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Re-resolutions triggered by layout are coalesced: one drain per
            // run-loop turn instead of one traversal per tagger per layout pass.
            PostHogTagResolutionCoalescer.markDirty(self)
        }

        private func setupAncestorObserver() {
            // Find the common ancestor and observe its subview changes
            // This handles cases like AsyncImage where content views change after initial setup
            guard
                let anchorView = postHogAnchor,
                let commonAncestor = anchorView.nearestCommonAncestor(with: self)
            else {
                return
            }

            // Remove any existing observer
            ancestorObserver?.stopObserving()

            // Create new observer for the common ancestor. On iOS 26 many taggers
            // share (nearly) the same ancestor, so a single hierarchy change used to
            // re-fire every tagger's traversal from its own observer — coalescing
            // collapses that storm into one resolution per tagger per turn.
            ancestorObserver = AncestorSubviewObserver(ancestor: commonAncestor) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    PostHogTagResolutionCoalescer.markDirty(self)
                }
            }
        }
    }

    /// A view of the tag machinery whose target resolution can be deferred and batched.
    @MainActor
    protocol PostHogCoalescedResolving: AnyObject {
        func performCoalescedResolution()
    }

    /// Coalesces re-resolution requests (layout passes, ancestor-hierarchy KVO signals)
    /// into a single drain per main-run-loop turn. Invalidation stays hierarchy-driven —
    /// the coalescer batches work, it never drops it: every marked resolver runs on the
    /// next drain, so content replaced without a geometry change is still re-tagged.
    @MainActor
    enum PostHogTagResolutionCoalescer {
        private struct WeakResolver {
            weak var value: (any PostHogCoalescedResolving)?
        }

        private static var dirtyResolvers: [ObjectIdentifier: WeakResolver] = [:]
        private static var isDrainScheduled = false

        static func markDirty(_ resolver: any PostHogCoalescedResolving) {
            dirtyResolvers[ObjectIdentifier(resolver)] = WeakResolver(value: resolver)
            guard !isDrainScheduled else { return }
            isDrainScheduled = true
            DispatchQueue.main.async {
                MainActor.assumeIsolated { drain() }
            }
        }

        private static func drain() {
            isDrainScheduled = false
            guard !dirtyResolvers.isEmpty else { return }
            let resolvers = dirtyResolvers.values.compactMap(\.value)
            dirtyResolvers.removeAll()
            for resolver in resolvers {
                resolver.performCoalescedResolution()
            }
        }

        #if TESTING
            static func drainForTesting() {
                drain()
            }
        #endif
    }

    extension PostHogTagUIView: PostHogCoalescedResolving {
        func performCoalescedResolution() {
            handler?()
        }
    }

    @available(iOS 26.0, *)
    extension PostHogFrameCaptureUIView: PostHogCoalescedResolving {
        func performCoalescedResolution() {
            detectLayers()
        }
    }

    /// Observes layer hierarchy changes on an ancestor view using KVO.
    /// This is used to detect when SwiftUI replaces content (e.g., AsyncImage loading).
    private final class AncestorSubviewObserver {
        private var observation: NSKeyValueObservation?

        init(ancestor: UIView, onChange: @escaping () -> Void) {
            // Use KVO on the layer's sublayers to detect hierarchy changes
            observation = ancestor.layer.observe(\.sublayers, options: [.new, .old]) { _, _ in
                // Dispatch async to allow the view hierarchy to settle
                DispatchQueue.main.async {
                    onChange()
                }
            }
        }

        func stopObserving() {
            observation?.invalidate()
            observation = nil
        }

        deinit {
            stopObserving()
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

        /// All descendants in pre-order DFS, excluding the receiver.
        var descendants: [UIView] {
            var result: [UIView] = []
            var stack: [UIView] = subviews.reversed()
            while let view = stack.popLast() {
                result.append(view)
                stack.append(contentsOf: view.subviews.reversed())
            }
            return result
        }

        /// The first view in the receiver's ancestor-or-self chain that is a PROPER
        /// ancestor of `other` (deliberately preserving the original semantics: the
        /// receiver itself qualifies, `other` itself never does). O(depth) via an
        /// ancestor set, replacing the O(depth²) isDescendant(of:) walk per step.
        func nearestCommonAncestor(with other: UIView) -> UIView? {
            var otherProperAncestors = Set<ObjectIdentifier>()
            var node = other.superview
            while let current = node {
                otherProperAncestors.insert(ObjectIdentifier(current))
                node = current.superview
            }

            var candidate: UIView? = self
            while let current = candidate {
                if otherProperAncestors.contains(ObjectIdentifier(current)) {
                    return current
                }
                candidate = current.superview
            }
            return nil
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
     Boxing a weak reference to a reference type.
     */
    final class Weak<T: AnyObject> {
        weak var value: T?

        init(_ wrappedValue: T? = nil) {
            value = wrappedValue
        }
    }

    #if TESTING
        /// Test-only entry points into the private tagging machinery.
        ///
        /// Used by the masking characterization tests, which pin the CURRENT resolution
        /// behavior of the traversal before it is optimized — so that later performance
        /// changes can prove they did not alter which views/layers get resolved.
        /// Lives in this file so it can reach `private` declarations. Not compiled into
        /// release builds.
        @MainActor
        enum PostHogTaggingTestSupport {
            /// Creates a real anchor/tagger pair registered in the `TaggingStore`,
            /// exactly like `PostHogTagViewModifier` does via its representables.
            static func makeTagPair(id: UUID = UUID()) -> (anchor: UIView, tagger: PostHogTagUIView) {
                (PostHogTagAnchorUIView(id: id), PostHogTagUIView(id: id, handler: nil))
            }

            static func targetViews(from tagger: PostHogTagUIView) -> [UIView] {
                getTargetViews(from: tagger)
            }

            /// Applies the same marking `markPostHogView` performs from the
            /// representables' `updateUIView` (the view and its direct superview).
            static func markInjected(_ view: UIView) {
                markPostHogView(view)
            }

            static func nearestCommonAncestor(of view: UIView, and other: UIView) -> UIView? {
                view.nearestCommonAncestor(with: other)
            }

            static func descendants(of view: UIView) -> [UIView] {
                Array(view.descendants)
            }

            @available(iOS 26.0, *)
            static func contentLayers(under layer: CALayer, containedIn referenceFrame: CGRect) -> [CALayer] {
                var results: [CALayer] = []
                collectContentLayers(from: layer, containedIn: referenceFrame, results: &results)
                return results
            }

            @available(iOS 26.0, *)
            static func makeFrameCaptureView() -> UIView {
                PostHogFrameCaptureUIView(id: UUID(), handler: nil)
            }

            @available(iOS 26.0, *)
            static func targetLayers(fromCaptureView captureView: UIView) -> [CALayer] {
                guard let captureView = captureView as? PostHogFrameCaptureUIView else { return [] }
                return getTargetLayers(from: captureView)
            }
        }
    #endif

#endif
