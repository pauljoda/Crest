import SwiftUI

/// A compact page's bar in search mode: one capsule that opens search for a
/// new tab, with New Tab inside it, in place of the address. The page's
/// address lives in the page menu instead. It shows the page loading as the
/// address bar does, and the palette grows out of it the same way. Touching
/// and holding it offers a new tab in another Space, or private browsing.
struct MobileCompactSearchBar: View {
    // MARK: - Static Variables

    /// The New Tab disc inside the capsule.
    private static let newTabSize: CGFloat = 36

    // MARK: - Variables

    let browser: BrowserStore
    let progress: Double
    let isLoading: Bool
    let search: () -> Void
    /// What touching and holding the bar offers besides a new tab here.
    let newTabChoices: MobileSearchModeControls
    let transition: MobileCompactChromeTransition
    let transitionEnded: (CGSize) -> Void
    /// Moves to the tab before or after the shown one, which VoiceOver offers
    /// as actions on the bar. Nil where the bar walks no tabs.
    var stepTab: ((AdjacentDirection) -> Void)?
    /// Whether the palette grown out of the bar shows, its input line in the
    /// bar's place.
    var isPaletteShown = false
    /// The namespace in which the palette grows out of the bar.
    var commandSurfaceNamespace: Namespace.ID?
    var commandPaletteHandoff = BrowserCommandPaletteHandoff.neither

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // A tap searches for a new tab here; touching and holding opens the
        // menu from the bar, which keeps its glass in place.
        Menu {
            newTabMenu
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Search or Enter URL…")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .browserReadableForeground(over: .accentColor)
                    .frame(
                        width: Self.newTabSize, height: Self.newTabSize
                    )
                    .background(Color.accentColor, in: .circle)
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(.capsule)
        } primaryAction: {
            search()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .background {
            Capsule()
                .fill(.tint.opacity(isLoading ? BrowserSidebarAddressFieldMetrics.loadingFillOpacity : 0))
                .scaleEffect(x: loadingProgress, anchor: .leading)
                .mask(Capsule())
                .animation(CrestMotion.loadingProgress.unlessReducingMotion(reduceMotion), value: loadingProgress)
        }
        // The palette grown out of the bar takes its place, as it does the
        // address bar's.
        .animation(commandPaletteHandoff.fieldAnimation.unlessReducingMotion(reduceMotion)) {
            $0.opacity(isPaletteShown ? 0 : 1)
        }
        .glassEffect(isPaletteShown ? .identity : .regular.interactive(), in: .capsule)
        .anchorPreference(key: MobileCompactCommandPaletteLayer.FieldAnchor.self, value: .bounds) { $0 }
        .background { commandPaletteAnchor }
        .allowsHitTesting(!isPaletteShown)
        .accessibilityHidden(isPaletteShown)
        .accessibilityLabel("Search or Enter URL")
        .accessibilityHint("Opens search for a new tab")
        .accessibilityIdentifier("search-mode-field")
        .modifier(MobileTabStepActions(step: stepTab))
        .modifier(MobileCompactChromeTransitionModifier(transition: transition, transitionEnded: transitionEnded))
    }

    /// A new tab here or in another Space, and the way in or out of private
    /// browsing.
    @ViewBuilder
    private var newTabMenu: some View {
        Group {
            Button("New Tab", systemImage: "plus", action: search)
            ForEach(newTabChoices.otherSpaces) { space in
                Button {
                    newTabChoices.searchInSpace(space.id)
                } label: {
                    BrowserSpaceIdentityLabel(
                        space: space, title: String(localized: "New Tab in \(space.identity.name)"))
                }
            }
            Divider()
            Button(
                newTabChoices.isPrivateBrowsing ? "Leave Private Browsing" : "Private Browsing",
                systemImage: ShortcutCommand.newPrivateWindow.symbol,
                action: newTabChoices.togglePrivateBrowsing
            )
        }
        .crestMenuActionLabelStyle()
    }

    /// The bar's frame, carrying the palette's identity while the bar holds
    /// it, so the palette's glass grows out of the bar's.
    @ViewBuilder
    private var commandPaletteAnchor: some View {
        if commandPaletteHandoff.fieldHoldsMorph, let commandSurfaceNamespace, let space = browser.shownSpace {
            Color.clear.matchedGeometryEffect(
                id: BrowserCommandSurfaceMorph.commandPalette(spaceID: space.id),
                in: commandSurfaceNamespace,
                properties: .frame,
                anchor: .center,
                isSource: true
            )
        }
    }

    private var loadingProgress: CGFloat {
        isLoading ? CGFloat(min(max(progress, 0.04), 1)) : 0
    }
}
