import SwiftUI

struct BrowserPeekPageCard: View {
    let model: BrowserPeekModel
    let showsInitialLoadingSurface: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool

    var body: some View {
        ZStack {
            BrowserPeekPageContent(
                page: model.page,
                browser: model.browser,
                pages: model.pages,
                wasReleasedForMemoryPressure:
                    model.pageLease?.wasReleasedForMemoryPressure == true,
                restore: model.restorePage
            )
            if showsInitialLoadingSurface {
                BrowserPeekInitialLoadingSurface()
            }
        }
        .animation(revealAnimation, value: showsInitialLoadingSurface)
        .modifier(
            BrowserPeekPageCardStyleModifier(
                reduceTransparency: reduceTransparency
            )
        )
    }

    private var revealAnimation: Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            BrowserPeekPresentationPolicy.initialContentRevealAnimation,
            reduceMotion: reduceMotion
        )
    }
}

private struct BrowserPeekPageContent: View {
    let page: BrowserPage?
    let browser: BrowserStore
    let pages: BrowserPagePool?
    let wasReleasedForMemoryPressure: Bool
    let restore: () -> Void

    var body: some View {
        if let page, let pages {
            BrowserWebContentView(
                page: page,
                browser: browser,
                pages: pages
            )
        } else if wasReleasedForMemoryPressure {
            BrowserPeekReleasedPageView(restore: restore)
        } else {
            BrowserPeekLoadingPageView()
        }
    }
}

private struct BrowserPeekInitialLoadingSurface: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading Peek")
            }
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

private struct BrowserPeekLoadingPageView: View {
    var body: some View {
        ProgressView("Opening Peek…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
    }
}

private struct BrowserPeekReleasedPageView: View {
    let restore: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Peek Released", systemImage: "memorychip")
        } description: {
            Text("Crest released this temporary page to reduce memory use.")
        } actions: {
            Button("Reload Peek", action: restore)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct BrowserPeekPageCardStyleModifier: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        content
            .clipShape(.rect(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
            }
            .shadow(
                color: .black.opacity(reduceTransparency ? 0 : 0.34),
                radius: 28,
                y: 14
            )
    }
}
