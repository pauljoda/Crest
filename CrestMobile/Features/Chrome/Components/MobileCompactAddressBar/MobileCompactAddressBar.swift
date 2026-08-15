import SwiftUI

struct MobileCompactAddressBar: View {
    let browser: BrowserStore
    @Binding var text: String
    @Binding var isEditing: Bool
    let isSecure: Bool
    let progress: Double
    let isLoading: Bool
    let pageActions: (any MobilePageActions)?
    let hideToolbar: (() -> Void)?
    let reloadOrStop: (() -> Void)?
    let transition: MobileCompactChromeTransition
    let transitionEnded: (CGSize) -> Void
    let beginNewTab: () -> Void
    let submit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            if let pageActions, pageActions.isAvailable, !isEditing {
                MobilePageActionsMenu(
                    browser: browser,
                    pages: pageActions,
                    systemImage: "ellipsis.circle",
                    hideToolbar: hideToolbar,
                    controlSize: MobileCompactAddressBarLayout.pageActionsControlSize
                )
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

#Preview("Compact Address Bar") {
    @Previewable @State var text = "example.com"
    @Previewable @State var isEditing = false
    let fixture = MobilePageActionsPreviewFixture()

    MobileCompactAddressBar(
        browser: fixture.browser,
        text: $text,
        isEditing: $isEditing,
        isSecure: true,
        progress: 0.62,
        isLoading: true,
        pageActions: fixture.actions,
        hideToolbar: nil,
        reloadOrStop: {},
        transition: .revealTabViewer,
        transitionEnded: { _ in },
        beginNewTab: {},
        submit: {}
    )
    .padding()
    .frame(width: 390)
}
