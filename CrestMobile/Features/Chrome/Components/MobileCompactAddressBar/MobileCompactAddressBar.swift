import SwiftUI

struct MobileCompactAddressBar: View {
    let browser: BrowserStore
    @Binding var text: String
    @Binding var isEditing: Bool
    let isSecure: Bool
    let progress: Double
    let isLoading: Bool
    let pageActions: MobileSelectedPageActionPort?
    let downloadsAccess: MobileDownloadsMenuAccess?
    let hideToolbar: (() -> Void)?
    let reloadOrStop: (() -> Void)?
    let transition: MobileCompactChromeTransition
    let transitionEnded: (CGSize) -> Void
    let beginNewTab: () -> Void
    let submit: () -> Void
    /// Moves to the tab before or after the shown one, which VoiceOver offers
    /// as actions on the address. Nil where the bar walks no tabs.
    var stepTab: ((AdjacentDirection) -> Void)?
    /// Opens the command palette over the bar, which a tap on the address
    /// does; without it the address edits in place.
    var openPalette: (() -> Void)?
    /// Whether the palette grown out of the bar shows, its input line in the
    /// bar's place.
    var isPaletteShown = false
    /// The namespace in which the palette grows out of the bar.
    var commandSurfaceNamespace: Namespace.ID?
    var commandPaletteHandoff = BrowserCommandPaletteHandoff.neither

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        HStack(spacing: MobileCompactAddressBarLayout.itemSpacing) {
            if let pageActions, pageActions.isAvailable, !isEditing {
                HStack(spacing: 0) {
                    MobilePageActionsMenu(
                        browser: browser,
                        pages: pageActions,
                        systemImage: "ellipsis.circle",
                        downloadsAccess: downloadsAccess,
                        hideToolbar: hideToolbar,
                        controlSize: MobileCompactAddressBarLayout.pageActionsControlSize
                    )
                    if let page = pageActions.activePage {
                        BrowserTranslationMenu(translation: page.translation)
                            .gesture(MobileTranslationLongPressGesture(action: page.translation.start))
                            .accessibilityHint("Tap for options. Touch and hold to translate now.")
                            .frame(width: MobileCompactAddressBarLayout.translationControlWidth)
                            .scaleEffect(offersTranslation || reduceMotion ? 1 : 0.4)
                            .offset(x: translationOffset, y: offersTranslation || reduceMotion ? 0 : 3)
                            .opacity(offersTranslation ? 1 : 0)
                            .padding(.leading, MobileCompactAddressBarLayout.translationLeadingGap)
                            .frame(
                                width: offersTranslation ? MobileCompactAddressBarLayout.translationSlotWidth : 0,
                                alignment: .leading
                            )
                            .allowsHitTesting(offersTranslation)
                            .accessibilityHidden(!offersTranslation)
                            .zIndex(1)
                    }
                }
            } else {
                Image(systemName: isSecure ? "lock.fill" : "magnifyingglass")
                    .font(CrestTypography.compactControlGlyph)
                    .foregroundStyle(.secondary)
                    .frame(width: MobileCompactAddressBarLayout.leadingGlyphWidth)
                    .accessibilityHidden(true)
            }

            BrowserAddressContent(
                text: $text,
                isEditing: $isEditing,
                activate: openPalette,
                longPressAction: beginNewTab,
                display: BrowserDeviceAppearanceStore.shared.address.display,
                submit: submit
            )
            .modifier(MobileTabStepActions(step: isEditing ? nil : stepTab))

            if isEditing, !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .frame(
                        width: MobileCompactAddressBarLayout.clearControlSize.width,
                        height: MobileCompactAddressBarLayout.clearControlSize.height)
            } else if reloadOrStop != nil {
                BrowserReloadControl(
                    isLoading: isLoading,
                    isDeveloperMode: pageActions?.activeURL?.isLocalDevelopmentAddress == true,
                    reloadOrStop: performReloadOrStop,
                    reload: performReload,
                    reloadFromOrigin: performReloadFromOrigin,
                    clearCookiesAndReload: clearCookiesAndReload,
                    isEnabled: pageActions?.isAvailable == true,
                    reloadControlSize: MobileCompactAddressBarLayout.reloadControlSize,
                    menuControlSize: MobileCompactAddressBarLayout.reloadMenuControlSize
                )
                .buttonStyle(.plain)
            }
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.18)
                : offersTranslation ? .spring(duration: 0.42, bounce: 0.08) : .easeOut(duration: 0.16),
            value: offersTranslation
        )
        .padding(.horizontal, MobileCompactAddressBarLayout.horizontalPadding)
        .frame(maxWidth: .infinity, minHeight: MobileCompactAddressBarLayout.minimumHeight)
        .contentShape(.capsule)
        .background {
            fieldShape
                .fill(.tint.opacity(isLoading ? BrowserSidebarAddressFieldMetrics.loadingFillOpacity : 0))
                .scaleEffect(x: loadingProgress, anchor: .leading)
                .mask(fieldShape)
                .animation(
                    CrestMotion.loadingProgress.unlessReducingMotion(reduceMotion),
                    value: loadingProgress
                )
        }
        // The palette grown out of the bar takes its place. The bar's glass
        // container draws the glass, so the glass itself steps aside rather
        // than fading with the bar's contents.
        .animation(commandPaletteHandoff.fieldAnimation.unlessReducingMotion(reduceMotion)) {
            $0.opacity(isPaletteShown ? 0 : 1)
        }
        .glassEffect(isPaletteShown ? .identity : .regular.interactive(), in: fieldShape)
        .anchorPreference(key: MobileCompactCommandPaletteLayer.FieldAnchor.self, value: .bounds) { $0 }
        .background { commandPaletteAnchor }
        .allowsHitTesting(!isPaletteShown)
        .accessibilityHidden(isPaletteShown)
        .modifier(
            MobileCompactChromeTransitionModifier(
                transition: transition,
                transitionEnded: transitionEnded
            )
        )
    }

    /// The bar's frame, carrying the palette's identity while the bar holds
    /// it, so the palette's surface grows out of the bar's glass.
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

    private var offersTranslation: Bool {
        pageActions?.activePage.map { $0.translation.isOffered && !$0.readerModeState.isActive } ?? false
    }

    private var translationOffset: CGFloat {
        guard !offersTranslation, !reduceMotion else { return 0 }
        // Keep the native menu alive before detection, so its construction does
        // not interrupt the animation from the neighboring Page Actions button.
        let distance = MobileCompactAddressBarLayout.pageActionsControlSize.width / 2 + 8 + 22
        return layoutDirection == .leftToRight ? -distance : distance
    }

    private var loadingProgress: CGFloat {
        isLoading ? CGFloat(min(max(progress, 0.04), 1)) : 0
    }

    private var fieldShape: Capsule {
        Capsule()
    }

    private func performReloadOrStop() {
        reloadOrStop?()
    }

    private func performReload() {
        if let pageActions {
            pageActions.reload()
        } else {
            reloadOrStop?()
        }
    }

    private func performReloadFromOrigin() {
        pageActions?.reloadFromOrigin()
    }

    private func clearCookiesAndReload() async {
        await pageActions?.clearSiteData(.siteData)
    }
}
