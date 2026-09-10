//
//  Regression tests for masks left behind by a screen that is covered but still attached
//  to the window. UIKit keeps the presenter's view in the hierarchy for an over-full-screen
//  presentation, and newer OS versions do the same for SwiftUI's `fullScreenCover`, so a
//  `postHogMask()` reporter on the covered screen kept reporting its rect and the capture
//  path painted it over the cover.
//

#if os(iOS) && canImport(SwiftUI)
    import Combine
    import Foundation
    @testable import PostHog
    import SwiftUI
    import Testing
    import UIKit

    @Suite("Replay masking behind a cover", .serialized)
    @MainActor
    struct PostHogMaskPresentationTest {
        private static let secret = "SSN 123-45-6789"

        // MARK: - Harness

        private final class CoverModel: ObservableObject {
            @Published var isPresented = false
        }

        @available(iOS 14.0, *)
        private struct MaskedScreen: View {
            @ObservedObject var model: CoverModel

            var body: some View {
                VStack {
                    Text("Visible label")
                    Text(PostHogMaskPresentationTest.secret).postHogMask()
                }
                .fullScreenCover(isPresented: $model.isPresented) {
                    ZStack {
                        Color.white.ignoresSafeArea()
                        Text("Cover")
                    }
                }
            }
        }

        private func maskRects(_ screen: Host) -> [CGRect] {
            PostHogReplayIntegration().collectMaskableRects(in: screen.window) ?? []
        }

        /// Presentation completes over several run loop turns, so poll instead of assuming
        /// one settle pass is enough.
        private func waitUntil(_ window: UIWindow, _ condition: () -> Bool) -> Bool {
            for _ in 0 ..< 20 {
                if condition() { return true }
                settle(window)
            }
            return condition()
        }

        /// A view controller whose view fills the window, kept over the presenter so the
        /// covered screen stays attached — the shape the defect needs.
        private func presentCover(over screen: Host, background: UIColor) -> UIViewController {
            let cover = UIViewController()
            cover.modalPresentationStyle = .overFullScreen
            cover.view.backgroundColor = background
            screen.controller.present(cover, animated: false)
            #expect(waitUntil(screen.window) { cover.view.window === screen.window })
            return cover
        }

        // MARK: - Tests

        @available(iOS 14.0, *)
        @Test("a SwiftUI fullScreenCover drops the masks of the screen it covers")
        func fullScreenCoverDropsMasksBehindIt() {
            let model = CoverModel()
            let screen = host(MaskedScreen(model: model))
            #expect(!maskRects(screen).isEmpty)

            model.isPresented = true
            #expect(waitUntil(screen.window) { screen.controller.presentedViewController != nil })
            #expect(maskRects(screen).isEmpty)

            model.isPresented = false
            #expect(waitUntil(screen.window) { screen.controller.presentedViewController == nil })
            // The screen is on top again, so its mask has to come back.
            #expect(!maskRects(screen).isEmpty)
        }

        @Test("an opaque cover that keeps the presenter attached drops its masks")
        func opaqueCoverDropsMasksBehindIt() {
            let screen = host(Text(Self.secret).postHogMask())
            #expect(!maskRects(screen).isEmpty)

            let cover = presentCover(over: screen, background: .white)
            // The covered screen is still in the window: this is the state the fix reads.
            #expect(screen.controller.view.window === screen.window)
            #expect(maskRects(screen).isEmpty)

            cover.dismiss(animated: false)
            #expect(waitUntil(screen.window) { screen.controller.presentedViewController == nil })
            #expect(!maskRects(screen).isEmpty)
        }

        @Test("a see-through cover keeps the masks behind it")
        func transparentCoverKeepsMasks() {
            let screen = host(Text(Self.secret).postHogMask())
            _ = presentCover(over: screen, background: .clear)
            // The masked content still shows through, so redacting it is the only safe answer.
            #expect(!maskRects(screen).isEmpty)
        }

        @Test("a hidden ancestor drops a reporter's mask")
        func hiddenAncestorDropsMask() {
            let screen = host(Text(Self.secret).postHogMask())
            #expect(!maskRects(screen).isEmpty)

            // Nothing under a hidden view is drawn, so nothing under it can need redacting.
            screen.controller.view.isHidden = true
            #expect(maskRects(screen).isEmpty)

            screen.controller.view.isHidden = false
            #expect(!maskRects(screen).isEmpty)
        }
    }
#endif
