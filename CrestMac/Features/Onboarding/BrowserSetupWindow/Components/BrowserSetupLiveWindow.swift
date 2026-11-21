import SwiftUI

/// The window of Crest setup builds, beside the steps: Crest's own browser
/// view over the live copy of what setup would leave, opening on the Start
/// Page, at its real size, as a window in the room beside the steps. Its web
/// pages stay unloaded, which a line in the page's place says.
struct BrowserSetupLiveWindow: View {
    // MARK: - Variables

    let session: BrowserSetupLiveSession
    /// How round the window's corners are; none once it fills the setup
    /// window.
    var cornerRadius = BrowserSetupLiveWindowMetrics.cornerRadius

    // MARK: - Actions - Drawing

    var body: some View {
        if let copy = session.copy {
            BrowserSetupLiveWindowHost(content: browser(copy), cornerRadius: cornerRadius)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: CrestLayout.hairline)
                        .allowsHitTesting(false)
                }
                .background { shadow }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Preview of Crest"))
        }
    }

    /// The window's shadow on the room, cast by a plain shape behind it
    /// rather than by the browser it hosts, which would be worked out again
    /// from the browser's views on every frame the window moves or grows.
    /// It goes once the window fills the setup window.
    private var shadow: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CrestBrandPalette.ink)
            .crestElevation(.window, scale: cornerRadius > 0 ? 1 : 0)
    }

    /// Crest's browser over the copy, with the copy's own core, a line where
    /// a web page would load, and nothing of the window around it to style.
    private func browser(_ copy: BrowserPlatformSetupLiveCopy) -> some View {
        BrowserRootView(
            browser: copy.store,
            pages: copy.pages,
            chrome: copy.chrome,
            transientBrowsing: copy.transientBrowsing,
            initialSidebarWidth: Double(BrowserChromeLayout.sidebarIdealWidth),
            persistSidebarWidth: { _ in }
        )
        .id(copy.id)
        .overlay {
            if showsWebPage(in: copy.store) {
                Text("Pages open once you start browsing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.leading, BrowserChromeLayout.sidebarIdealWidth)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) { windowButtons }
        .environment(copy.store.core)
        .environment(\.browserRootStylesWindow, false)
        // The copy shows what setup will leave; its Start Page waits to be
        // clicked rather than taking the keyboard from setup.
        .environment(\.commandPaletteFocusesOnShow, false)
        .environment(\.browserApplicationIcon, Image(nsImage: NSApplication.shared.applicationIconImage))
        .tint(CrestBrandTheme.accent)
    }
}

extension BrowserSetupLiveWindow {
    /// The window's three buttons where a Crest window shows them, dimmed as
    /// a window in the background shows them, so the copy reads as a window.
    private var windowButtons: some View {
        HStack(spacing: BrowserSetupLiveWindowMetrics.windowButtonSpacing) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color.primary.opacity(0.2))
                    .overlay { Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: CrestLayout.hairline) }
                    .frame(
                        width: BrowserSetupLiveWindowMetrics.windowButton,
                        height: BrowserSetupLiveWindowMetrics.windowButton)
            }
        }
        .padding(BrowserSetupLiveWindowMetrics.windowButtonInset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Actions - Reading

    /// Whether the copy shows a web page, which it never loads, rather than a
    /// Start Page or one of Crest's own pages.
    private func showsWebPage(in store: BrowserStore) -> Bool {
        guard let space = store.shownSpace, let tabID = store.selectedTabID(in: space.id),
            let tab = space.tabs.model(tabID)
        else { return false }
        return !tab.isStartPage && tab.nativeTabContent == nil
    }
}

enum BrowserSetupLiveWindowMetrics {
    static let cornerRadius: CGFloat = 14
    static let windowButton: CGFloat = 13
    static let windowButtonSpacing: CGFloat = 9
    static let windowButtonInset = EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 0)
}
