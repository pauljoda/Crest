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
    let clearCookiesAndReload: () async -> Void
    var isEnabled = true
    var reloadControlSize = CGSize(
        width: CrestLayout.minimumHitTarget,
        height: CrestLayout.minimumHitTarget
    )
    var menuControlSize = CGSize(
        width: CrestLayout.minimumHitTarget,
        height: CrestLayout.minimumHitTarget
    )
    var symbolPointSize = BrowserChromeSymbolLabel.defaultPointSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reloadPulse = 0
    @State private var isPlayingReloadFeedback = false
    @State private var isClearingSiteData = false
    /// Whether the control shows stop, once a load has run long enough to
    /// be seen.
    @State private var showsStop = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: performPrimaryAction) {
                BrowserReloadFeedbackIcon(
                    systemName: symbolName,
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
                    Group {
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
                            "Clear Cookies and Reload",
                            systemImage: BrowsingDataCategory.siteData.symbol ?? "trash"
                        ) {
                            clearAndReload()
                        }
                        .disabled(isClearingSiteData)
                    }
                    .crestMenuActionLabelStyle()
                } label: {
                    Image(systemName: isClearingSiteData ? "progress.indicator" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .frame(
                            width: menuControlSize.width,
                            height: menuControlSize.height
                        )
                        .contentShape(.rect)
                }
                .crestMenuActionLabelStyle()
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
        .task(id: isLoading) {
            await showStop(isLoading)
        }
    }

    /// Stop while a load runs, unless the reload feedback is still turning.
    private var symbolName: String {
        showsStop && !isPlayingReloadFeedback ? "xmark" : "arrow.clockwise"
    }

    /// Fades to stop once a load has run for `CrestMotion.stopSymbolDelay`,
    /// and back to reload as soon as it ends.
    private func showStop(_ loading: Bool) async {
        if loading {
            try? await Task.sleep(for: CrestMotion.stopSymbolDelay)
            guard !Task.isCancelled else { return }
        }
        guard showsStop != loading else { return }
        withAnimation(CrestMotion.controlState.unlessReducingMotion(reduceMotion)) {
            showsStop = loading
        }
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
            await clearCookiesAndReload()
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

#if DEBUG
    #Preview("Reload, stop, and developer menu") {
        @Previewable @State var loading = false
        VStack {
            BrowserReloadControl(
                isLoading: loading, isDeveloperMode: true, reloadOrStop: { loading.toggle() },
                reload: { loading = true }, reloadFromOrigin: { loading = true }, clearCookiesAndReload: {})
            Toggle("Loading", isOn: $loading)
        }.padding().frame(width: 240)
    }
#endif
