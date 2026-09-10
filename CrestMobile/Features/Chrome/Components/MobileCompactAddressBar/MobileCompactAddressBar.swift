import SwiftUI

struct MobileCompactAddressBar: View {
    let browser: BrowserStore
    @Binding var text: String
    @Binding var isEditing: Bool
    let isSecure: Bool
    let progress: Double
    let isLoading: Bool
    let pageActions: (any MobilePageActions)?
    let downloadsAccess: MobileDownloadsMenuAccess?
    let hideToolbar: (() -> Void)?
    let reloadOrStop: (() -> Void)?
    let transition: MobileCompactChromeTransition
    let transitionEnded: (CGSize) -> Void
    let beginNewTab: () -> Void
    let submit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        HStack(spacing: 8) {
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
                            .frame(width: 44)
                            .scaleEffect(offersTranslation || reduceMotion ? 1 : 0.4)
                            .offset(x: translationOffset, y: offersTranslation || reduceMotion ? 0 : 3)
                            .opacity(offersTranslation ? 1 : 0)
                            .padding(.leading, 8)
                            .frame(width: offersTranslation ? 52 : 0, alignment: .leading)
                            .allowsHitTesting(offersTranslation)
                            .accessibilityHidden(!offersTranslation)
                            .zIndex(1)
                    }
                }
            } else {
                Image(systemName: isSecure ? "lock.fill" : "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }

            BrowserAddressContent(
                text: $text,
                isEditing: $isEditing,
                longPressAction: beginNewTab,
                submit: submit
            )

            if isEditing, !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 36)
            } else if reloadOrStop != nil {
                BrowserReloadControl(
                    isLoading: isLoading,
                    isDeveloperMode: BrowserDeveloperModePolicy.isAutomatic(
                        for: pageActions?.activeURL
                    ),
                    reloadOrStop: performReloadOrStop,
                    reload: performReload,
                    reloadFromOrigin: performReloadFromOrigin,
                    clearSiteDataAndReload: clearSiteDataAndReload,
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
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(.capsule)
        .background {
            fieldShape
                .fill(.tint.opacity(isLoading ? 0.2 : 0))
                .scaleEffect(x: loadingProgress, anchor: .leading)
                .mask(fieldShape)
                .animation(
                    BrowserVisualAccessibilityPolicy.animation(
                        CrestMotion.loadingProgress,
                        reduceMotion: reduceMotion
                    ),
                    value: loadingProgress
                )
        }
        .glassEffect(.regular.interactive(), in: fieldShape)
        .modifier(
            MobileCompactChromeTransitionModifier(
                transition: transition,
                transitionEnded: transitionEnded
            )
        )
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

    private func clearSiteDataAndReload() async {
        await pageActions?.clearSiteDataAndReload()
    }
}
