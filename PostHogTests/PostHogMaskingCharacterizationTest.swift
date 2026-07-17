//
//  PostHogMaskingCharacterizationTest.swift
//  PostHog
//
//  Created by Jiri Urbasek on 16/07/2026.
//

#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    /// Characterization tests pinning the CURRENT behavior of the SwiftUI masking
    /// machinery: the tag-view traversal (`getTargetViews` and its helpers), the
    /// iOS 26 content-layer collection, and the capture-side consumption of the
    /// `postHogNoCapture` flag (`findMaskableWidgets`).
    ///
    /// These are golden tests: they encode what the SDK does today — including
    /// behaviors that are quirky but relied upon — so that the performance rework
    /// of this machinery can prove it did not change resolution behavior. They are
    /// intentionally written against synthetic UIKit hierarchies (not hosted
    /// SwiftUI) so they are deterministic and OS-rendering independent.
    ///
    /// Known-buggy behaviors that these tests deliberately do NOT pin (they are
    /// slated to change, with their own tests, in later commits): the Boolean
    /// unmask-on-remove of overlapping masks (`postHogMask()`'s `onRemove`), and
    /// the hosting-view-sized reference frame of the iOS 26 layer scan.
    @Suite("SwiftUI masking characterization", .serialized)
    @MainActor
    final class PostHogMaskingCharacterizationTest {
        // MARK: - getTargetViews

        @Test("targets are the DFS pre-order views between anchor and tagger, excluding injected views")
        func targetViewsFlatSandwich() {
            let (anchor, tagger) = PostHogTaggingTestSupport.makeTagPair()

            let root = UIView()
            let contentA = UIView()
            let childOfA = UIView()
            let contentB = UIView()

            contentA.addSubview(childOfA)
            root.addSubview(anchor)
            root.addSubview(contentA)
            root.addSubview(contentB)
            root.addSubview(tagger)

            let targets = PostHogTaggingTestSupport.targetViews(from: tagger)

            #expect(targets.count == 3)
            #expect(targets.elementsEqual([contentA, childOfA, contentB], by: ===))
        }

        @Test("wrapper hosts: anchor-side wrapper is dropped by traversal order, tagger-side wrapper only if marked injected")
        func targetViewsWrappedSandwich() {
            let (anchor, tagger) = PostHogTaggingTestSupport.makeTagPair()

            // Mirrors the structure the representables produce: anchor/tagger sit
            // inside platform-host wrapper views, and `updateUIView` marks the
            // wrapper (superview) as an injected view.
            let root = UIView()
            let anchorHost = UIView()
            let stack = UIView()
            let label1 = UIView()
            let label2 = UIView()
            let taggerHost = UIView()

            anchorHost.addSubview(anchor)
            stack.addSubview(label1)
            stack.addSubview(label2)
            taggerHost.addSubview(tagger)
            root.addSubview(anchorHost)
            root.addSubview(stack)
            root.addSubview(taggerHost)

            PostHogTaggingTestSupport.markInjected(anchor)
            PostHogTaggingTestSupport.markInjected(tagger)

            let targets = PostHogTaggingTestSupport.targetViews(from: tagger)

            // anchorHost precedes the anchor in DFS order, so drop(while:) removes
            // it; taggerHost was marked injected (as the representable would), so
            // the filter removes it. What remains is the content in between.
            #expect(targets.elementsEqual([stack, label1, label2], by: ===))
        }

        @Test("tagger without a hierarchy resolves no targets")
        func targetViewsNotInHierarchy() {
            let (_, tagger) = PostHogTaggingTestSupport.makeTagPair()

            // Never added to a superview: the tagger's back-reference is only set
            // in didMoveToSuperview, so anchor lookup fails.
            #expect(PostHogTaggingTestSupport.targetViews(from: tagger).isEmpty)
        }

        @Test("anchor and tagger in disjoint trees resolve no targets")
        func targetViewsDisjointTrees() {
            let (anchor, tagger) = PostHogTaggingTestSupport.makeTagPair()

            let treeA = UIView()
            let treeB = UIView()
            treeA.addSubview(anchor)
            treeB.addSubview(tagger)

            #expect(PostHogTaggingTestSupport.targetViews(from: tagger).isEmpty)
        }

        // MARK: - Traversal helpers

        @Test("descendants enumerate in DFS pre-order, excluding the receiver")
        func descendantsPreOrder() {
            let root = UIView()
            let a = UIView()
            let a1 = UIView()
            let a2 = UIView()
            let b = UIView()
            let b1 = UIView()

            a.addSubview(a1)
            a.addSubview(a2)
            b.addSubview(b1)
            root.addSubview(a)
            root.addSubview(b)

            let result = PostHogTaggingTestSupport.descendants(of: root)
            #expect(result.elementsEqual([a, a1, a2, b, b1], by: ===))
        }

        @Test("nearest common ancestor of siblings is their parent")
        func nearestCommonAncestorSiblings() {
            let parent = UIView()
            let a = UIView()
            let b = UIView()
            parent.addSubview(a)
            parent.addSubview(b)

            #expect(PostHogTaggingTestSupport.nearestCommonAncestor(of: a, and: b) === parent)
        }

        @Test("quirk: for ancestor/descendant pairs the result skips ABOVE the ancestor")
        func nearestCommonAncestorAncestorDescendantQuirk() {
            // `isDescendant(of:)` here excludes self (ancestors drops the first
            // element), so walking up from the descendant never terminates AT the
            // ancestor — it terminates one level above it. Pinned as-is: the real
            // anchor/tagger pairs are never ancestor/descendant, so this quirk is
            // dormant, but a traversal rewrite must not accidentally "fix" visible
            // behavior while restructuring.
            let root = UIView()
            let mid = UIView()
            let leaf = UIView()
            root.addSubview(mid)
            mid.addSubview(leaf)

            #expect(PostHogTaggingTestSupport.nearestCommonAncestor(of: leaf, and: mid) === root)
            #expect(PostHogTaggingTestSupport.nearestCommonAncestor(of: leaf, and: root) == nil)
        }

        @Test("nearest common ancestor of disjoint trees is nil")
        func nearestCommonAncestorDisjoint() {
            #expect(PostHogTaggingTestSupport.nearestCommonAncestor(of: UIView(), and: UIView()) == nil)
        }

        // MARK: - iOS 26 content-layer collection

        @Test("content layers: collects sized, non-view-backed layers whose center is inside the reference frame")
        func contentLayerCollection() throws {
            guard #available(iOS 26.0, *) else { return }

            let referenceFrame = CGRect(x: 0, y: 0, width: 200, height: 200)
            let root = CALayer()
            root.frame = referenceFrame

            let content = CALayer()
            content.frame = CGRect(x: 10, y: 10, width: 50, height: 50)
            root.addSublayer(content)

            let zeroSized = CALayer()
            zeroSized.frame = .zero
            root.addSublayer(zeroSized)

            let viewBacked = CALayer()
            viewBacked.frame = CGRect(x: 20, y: 100, width: 50, height: 50)
            let backingView = UIView()
            viewBacked.delegate = backingView
            root.addSublayer(viewBacked)

            // Center outside the reference frame -> not collected itself, but
            // recursion continues into its children, which can still qualify.
            let outside = CALayer()
            outside.frame = CGRect(x: 150, y: 150, width: 300, height: 300)
            let childInside = CALayer()
            childInside.frame = CGRect(x: 0, y: 0, width: 20, height: 20) // absolute (150,150), center inside
            outside.addSublayer(childInside)
            root.addSublayer(outside)

            let collected = PostHogTaggingTestSupport.contentLayers(under: root, containedIn: referenceFrame)

            #expect(collected.elementsEqual([content, childInside], by: ===))
        }

        // MARK: - Capture-side flag consumption

        @Test("findMaskableWidgets returns the absolute rect of postHogNoCapture-flagged views, and only those")
        func maskableRectsForFlaggedViews() {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            let container = UIView(frame: window.bounds)
            let flagged = UIView(frame: CGRect(x: 10, y: 20, width: 100, height: 40))
            let plain = UIView(frame: CGRect(x: 10, y: 100, width: 100, height: 40))

            container.addSubview(flagged)
            container.addSubview(plain)
            window.addSubview(container)

            flagged.postHogNoCapture = true

            // A bare integration (no PostHogSDK attached) exercises the traversal
            // with all config-dependent heuristics off, isolating flag consumption.
            let integration = PostHogReplayIntegration()
            let rects = integration.debugMaskableRects(in: window)

            #expect(rects == [CGRect(x: 10, y: 20, width: 100, height: 40)])
        }

        @Test("iOS 26: findMaskableWidgets also returns rects for postHogNoCapture-flagged bare CALayers")
        func maskableRectsForFlaggedLayers() throws {
            guard #available(iOS 26.0, *) else { return }

            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            let container = UIView(frame: window.bounds)
            window.addSubview(container)

            let contentLayer = CALayer()
            contentLayer.frame = CGRect(x: 30, y: 60, width: 80, height: 20)
            container.layer.addSublayer(contentLayer)
            contentLayer.postHogNoCapture = true

            let integration = PostHogReplayIntegration()
            let rects = integration.debugMaskableRects(in: window)

            #expect(rects == [CGRect(x: 30, y: 60, width: 80, height: 20)])
        }
    }
#endif
