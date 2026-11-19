import SwiftUI

/// The Crest setup builds on iPhone and iPad: Crest's own browser over the
/// live copy of what setup would leave, opening on the Start Page. Its web
/// pages stay unloaded.
struct MobileSetupLiveWindow: View {
    // MARK: - Variables

    let session: MobileSetupLiveSession
    /// How round the copy's corners are; none once it fills the screen.
    var cornerRadius = MobileSetupLiveWindowMetrics.cornerRadius

    // MARK: - Actions - Drawing

    var body: some View {
        if let copy = session.copy {
            MobileSetupLiveWindowHost(content: browser(copy), cornerRadius: cornerRadius)
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

    /// The copy's shadow, cast by a plain shape behind it rather than by the
    /// browser it hosts, which would be worked out again from the browser's
    /// views on every frame the copy moves or grows. It goes once the copy
    /// fills the screen.
    private var shadow: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CrestBrandPalette.ink)
            .shadow(
                color: CrestBrandPalette.ink.opacity(cornerRadius > 0 ? MobileSetupLiveWindowMetrics.shadow : 0),
                radius: MobileSetupLiveWindowMetrics.shadowRadius, y: MobileSetupLiveWindowMetrics.shadowOffset)
    }

    /// Crest's browser over the copy, with the copy's own core.
    private func browser(_ copy: MobileSetupLiveSession.Copy) -> some View {
        MobileBrowserRootView(
            browser: copy.store,
            pages: copy.pages,
            dataDeleter: copy.pages,
            navigation: copy.navigation,
            transientBrowsing: copy.transientBrowsing,
            startupBehavior: .showStartPage,
            togglePrivateBrowsing: {},
            closePrivateBrowsing: {}
        )
        .id(copy.id)
        .environment(copy.store.core)
        .environment(copy.store.core.engines)
        .environment(\.browserInteractionCapabilities, BrowserInteractionCapabilities(supportsTouch: true))
        // The copy shows what setup will leave; its Start Page waits to be
        // tapped rather than raising the keyboard over setup.
        .environment(\.commandPaletteFocusesOnShow, false)
    }
}

enum MobileSetupLiveWindowMetrics {
    static let cornerRadius: CGFloat = 22
    static let shadow = 0.36
    static let shadowRadius: CGFloat = 26
    static let shadowOffset: CGFloat = 14
}
