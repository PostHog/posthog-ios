#if os(iOS)
    import CoreGraphics
    @testable import PostHog
    import Testing
    import UIKit

    @Suite("Replay screenshot renderer")
    @MainActor
    struct PostHogGraphicsImageRendererTest {
        /// Default upload size; its 1.4 MB bitmap comes from the allocator's reusable pool, so an
        /// uncleared buffer carries old heap bytes.
        private static let size = CGSize(width: 402, height: 874)
        private static let scale: CGFloat = 1
        private static let bytesPerRow = Int(size.width * scale) * 4
        private static let bufferSize = Int(size.height * scale) * bytesPerRow

        private func pixelBytes(_ image: UIImage?) throws -> [UInt8] {
            let data = try #require(image?.cgImage?.dataProvider?.data)
            return [UInt8](data as Data)
        }

        /// Seeds the allocator so the next same-size allocation returns non-zero bytes.
        private func dirtyHeap() {
            guard let block = malloc(Self.bufferSize) else { return }
            memset(block, 0xAB, Self.bufferSize)
            free(block)
        }

        @Test("a draw that paints nothing is fully transparent")
        func emptyDrawIsTransparent() throws {
            dirtyHeap()
            let image = PostHogGraphicsImageRenderer(size: Self.size, scale: Self.scale).image { _ in }

            let pixels = try pixelBytes(image)
            #expect(pixels.count == Self.bufferSize)
            #expect(pixels.allSatisfy { $0 == 0 })
        }

        @Test("a partial draw leaves the undrawn pixels transparent")
        func partialDrawLeavesRestTransparent() throws {
            dirtyHeap()
            let image = PostHogGraphicsImageRenderer(size: Self.size, scale: Self.scale).image { context in
                context.setFillColor(UIColor.red.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            }

            let pixels = try pixelBytes(image)
            // Top-left origin, so the red square fills the first rows.
            #expect(Array(pixels[0 ..< 4]) == [255, 0, 0, 255])
            #expect(pixels[(Self.bytesPerRow * 100)...].allSatisfy { $0 == 0 })
        }
    }
#endif
