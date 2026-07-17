//
//  PostHogMaskViewModifier.swift
//  PostHog
//
//  Created by Yiannis Josephides on 09/10/2024.
//

#if os(iOS) && canImport(SwiftUI)

    import SwiftUI

    /// SwiftUI session replay masking helpers.
    public extension View {
        /**
         Marks a SwiftUI View to be masked in PostHog session replay recordings.

         Use this modifier to explicitly mask sensitive views in session replay recordings.

         The masked region is reported through a single passive overlay view whose frame is
         read live at capture time, so the redaction can never go stale — a row that scrolled,
         animated, or was repositioned is redacted at its current position. This does not rely
         on mapping SwiftUI content to backing UIKit views, so it behaves identically across
         OS rendering engines (including iOS 26+).

         Note: an explicit `postHogMask()` always masks its region, even inside an area marked
         with `postHogNoMask()` — the explicit mask wins.

         For example:
         ```swift
         // This view will be masked in recordings
         SensitiveDataView()
            .postHogMask()

         // Conditionally mask based on a flag
         SensitiveDataView()
            .postHogMask(shouldMask)
         ```

         - Parameter isEnabled: Whether masking should be enabled. Defaults to true.
         - Returns: A modified view that will be masked in session replay recordings when enabled
         */
        func postHogMask(_ isEnabled: Bool = true) -> some View {
            overlay(
                PostHogMaskReporterView(isEnabled: isEnabled)
                    .allowsHitTesting(false)
                    .accessibility(hidden: true)
            )
        }
    }

    /// Registry of live "mask reporter" views. The capture side computes each reporter's
    /// rect at snapshot time via the same live geometry read used for flagged views —
    /// nothing is cached, so rects can never go stale. Storage is weak, which makes any
    /// missed teardown self-healing.
    ///
    /// Registration happens from view lifecycle callbacks (main thread) and reads happen
    /// from the snapshot path; the lock keeps the registry itself thread-safe, while rect
    /// computation touches UIKit and stays on the thread the capture path already uses
    /// for hierarchy access.
    final class PostHogSessionReplayMaskRegistry {
        static let shared = PostHogSessionReplayMaskRegistry()

        private let lock = NSLock()
        private var reporters: [ObjectIdentifier: Weak<UIView>] = [:]

        func register(_ reporter: UIView) {
            lock.withLock { reporters[ObjectIdentifier(reporter)] = Weak(reporter) }
        }

        func unregister(_ reporter: UIView) {
            lock.withLock { reporters[ObjectIdentifier(reporter)] = nil }
        }

        /// The rects to redact in `window`, read live from the registered reporters.
        /// Reporters attached to other windows (iPad multi-window) are excluded.
        func maskedRects(in window: UIWindow) -> [CGRect] {
            let liveReporters = lock.withLock {
                reporters = reporters.filter { $0.value.value != nil }
                return reporters.values.compactMap(\.value)
            }

            var rects: [CGRect] = []
            for reporter in liveReporters {
                guard reporter.window === window, reporter.isVisible() else { continue }
                let rect = reporter.toAbsoluteRect(window)
                if !rect.isEmpty {
                    rects.append(rect)
                }
            }
            return rects
        }

        #if TESTING
            var registeredCountForTesting: Int {
                lock.withLock { reporters.values.compactMap(\.value).count }
            }
        #endif
    }

    /// The single view `postHogMask()` injects: transparent, hit-test-disabled, spanning
    /// the masked view's extent. It does nothing except exist there and keep itself
    /// registered while attached to a window — no traversals, no KVO, no per-layout work.
    final class PostHogMaskReporterUIView: UIView {
        var isMaskingEnabled = true {
            didSet { updateRegistration() }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            postHogView = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Registration keys off window attachment: a reporter inside a freshly
            // realized lazy row is registered before the row can appear in a snapshot.
            updateRegistration()
        }

        private func updateRegistration() {
            if window != nil, isMaskingEnabled {
                PostHogSessionReplayMaskRegistry.shared.register(self)
            } else {
                PostHogSessionReplayMaskRegistry.shared.unregister(self)
            }
        }
    }

    struct PostHogMaskReporterView: UIViewRepresentable {
        let isEnabled: Bool

        func makeUIView(context _: Context) -> PostHogMaskReporterUIView {
            let view = PostHogMaskReporterUIView(frame: .zero)
            view.isMaskingEnabled = isEnabled
            return view
        }

        func updateUIView(_ uiView: PostHogMaskReporterUIView, context _: Context) {
            uiView.isMaskingEnabled = isEnabled
            uiView.postHogView = true
            uiView.superview?.postHogView = true
        }

        static func dismantleUIView(_ uiView: PostHogMaskReporterUIView, coordinator _: ()) {
            PostHogSessionReplayMaskRegistry.shared.unregister(uiView)
        }
    }

    /// Ref-counted flag ownership. A target can be claimed by several masks at once —
    /// overlapping target sets are the norm on iOS 26, where masks resolve against the
    /// shared hosting view — so a plain Boolean flag would let one mask's teardown
    /// (e.g. a lazy row scrolling offscreen) unmask targets still owned by another.
    /// A target stays flagged for as long as at least one owner claims it.
    final class PostHogFlagOwners {
        var owners: Set<ObjectIdentifier> = []
    }

    extension NSObject {
        func isPostHogFlagOwned(_ key: UnsafeRawPointer) -> Bool {
            (objc_getAssociatedObject(self, key) as? PostHogFlagOwners)?.owners.isEmpty == false
        }

        func setPostHogFlag(_ key: UnsafeRawPointer, enabled: Bool, owner: ObjectIdentifier) {
            let box: PostHogFlagOwners
            if let existing = objc_getAssociatedObject(self, key) as? PostHogFlagOwners {
                box = existing
            } else {
                box = PostHogFlagOwners()
                objc_setAssociatedObject(self, key, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            if enabled {
                box.owners.insert(owner)
            } else {
                box.owners.remove(owner)
            }
        }
    }

    extension UIView {
        /// Whether at least one mask currently claims this view.
        var postHogNoCapture: Bool {
            isPostHogFlagOwned(&AssociatedKeys.phNoCapture)
        }

        func setPostHogNoCapture(_ enabled: Bool, owner: ObjectIdentifier) {
            setPostHogFlag(&AssociatedKeys.phNoCapture, enabled: enabled, owner: owner)
        }
    }

    extension CALayer {
        /// Whether at least one mask currently claims this layer.
        var postHogNoCapture: Bool {
            isPostHogFlagOwned(&AssociatedKeys.phNoCapture)
        }

        func setPostHogNoCapture(_ enabled: Bool, owner: ObjectIdentifier) {
            setPostHogFlag(&AssociatedKeys.phNoCapture, enabled: enabled, owner: owner)
        }
    }
#endif
