import CoreImage
import SwiftUI
import WebKit

/// Only processed pixels reach the locked surface. It never mounts a WebKit
/// view, and a missing snapshot leaves the opaque access screen in place.
struct LockedSpacePagePreview: View {
    let space: BrowserSpace
    let pages: BrowserPagePool
    @State private var images: [TabID: CGImage] = [:]

    var body: some View {
        HStack(spacing: BrowserChromeLayout.pageBrandSeamWidth) {
            ForEach(space.presentedSplitMembers(for: space.selectedTabID)) { tab in
                GeometryReader { geometry in
                    if let image = images[tab.id] {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: BrowserSpaceRuntimeAssignment(space: space)) {
            var obscured: [TabID: CGImage] = [:]
            for tab in space.presentedSplitMembers(for: space.selectedTabID) {
                guard !Task.isCancelled else { return }
                guard
                    let page = pages.residentPage(
                        matching: BrowserTabRuntimeAssignment(
                            tabID: tab.id, spaceID: space.id, profileID: space.profile.id)),
                    let image = await snapshot(page.webView)
                else { continue }
                let blurred = await Task.detached(priority: .utility) { Self.obscure(image) }.value
                guard !Task.isCancelled else { return }
                obscured[tab.id] = blurred
            }
            images = obscured
        }
    }

    private func snapshot(_ webView: WKWebView) async -> CGImage? {
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        configuration.snapshotWidth = 256
        return await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, _ in
                continuation.resume(returning: image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            }
        }
    }

    nonisolated private static func obscure(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 24])
            .cropped(to: input.extent)
        return CIContext().createCGImage(output, from: input.extent)
    }
}
