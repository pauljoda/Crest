import SwiftUI

/// One reload interaction shared by compact address bars and the persistent
/// iPad/macOS sidebar chrome. Local developer pages gain the adjacent menu
/// without forking the control or its feedback animation.
struct BrowserReloadControl: View {
    let isLoading: Bool
    let isDeveloperMode: Bool
    let reloadOrStop: () -> Void
    let reload: () -> Void
    let reloadFromOrigin: () -> Void
    let clearSiteDataAndReload: () async -> Void
    var isEnabled = true
    var reloadControlSize = CGSize(
        width: CrestLayout.minimumHitTarget,
        height: CrestLayout.minimumHitTarget
    )
    var menuControlSize = CGSize(
        width: CrestLayout.minimumHitTarget,
        height: CrestLayout.minimumHitTarget
    )
    var symbolPointSize = BrowserReloadFeedbackPolicy.symbolPointSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reloadPulse = 0
    @State private var isPlayingReloadFeedback = false
    @State private var isClearingSiteData = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: performPrimaryAction) {
                BrowserReloadFeedbackIcon(
                    systemName: BrowserReloadFeedbackPolicy.symbolName(
                        isLoading: isLoading,
                        isPlayingFeedback: isPlayingReloadFeedback
                    ),
                    pulse: reloadPulse,
                    animates: !reduceMotion,
                    pointSize: symbolPointSize,
                    feedbackDidComplete: finishReloadFeedback
                )
            }
            .buttonStyle(CrestChromeButtonStyle(controlSize: reloadControlSize))
            .accessibilityLabel(isLoading ? "Stop" : "Reload")
            .accessibilityIdentifier("reload-control")
            .help(isLoading ? "Stop" : "Reload (⌘R)")

            if isDeveloperMode {
                Menu {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        performAnimatedReload(reload)
                    }
                    Button(
                        "Reload (Ignore Cache)",
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
                    ) {
                        performAnimatedReload(reloadFromOrigin)
                    }
                    Divider()
                    Button(
                        "Clear Cookies, Storage, and Reload",
                        systemImage: "trash"
                    ) {
                        clearAndReload()
                    }
                    .disabled(isClearingSiteData)
                } label: {
                    Image(systemName: isClearingSiteData ? "progress.indicator" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .frame(
                            width: menuControlSize.width,
                            height: menuControlSize.height
                        )
                        .contentShape(.rect)
                }
                .menuIndicator(.hidden)
                .menuStyle(.button)
                .buttonStyle(CrestChromeButtonStyle(controlSize: menuControlSize))
                .accessibilityLabel("Reload options")
                .accessibilityIdentifier("developer-reload-menu")
                .help("Reload Options")
            }
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(
            isEnabled
                ? Color.secondary
                : Color.secondary.opacity(CrestOpacity.controlDisabledForeground)
        )
        .disabled(!isEnabled)
    }

    private func performPrimaryAction() {
        guard !isLoading else {
            reloadOrStop()
            return
        }
        performAnimatedReload(reloadOrStop)
    }

    private func performAnimatedReload(_ action: () -> Void) {
        beginReloadFeedback()
        action()
    }

    private func clearAndReload() {
        guard !isClearingSiteData else { return }
        isClearingSiteData = true
        beginReloadFeedback()
        Task { @MainActor in
            await clearSiteDataAndReload()
            isClearingSiteData = false
        }
    }

    private func beginReloadFeedback() {
        isPlayingReloadFeedback = !reduceMotion
        reloadPulse += 1
    }

    private func finishReloadFeedback(_ completedPulse: Int) {
        guard completedPulse == reloadPulse else { return }
        isPlayingReloadFeedback = false
    }
}
