import SwiftUI

/// The sidebar's back, forward, and reload strip, on every shell.
///
/// Everything the strip needs from the page layer arrives through
/// `BrowserSidebarNavigationPort`, and everything about how it is drawn comes
/// from `BrowserInteractionCapabilities` — so the two shells share this strip
/// rather than a resemblance. What is left is one slot at the trailing end for
/// a shell that keeps its page menu there.
struct BrowserSidebarNavigationControls<TrailingAccessory: View>: View {
    private let port: BrowserSidebarNavigationPort
    private let capabilities: BrowserInteractionCapabilities
    private let trailingAccessory: TrailingAccessory

    /// Back and forward both stay in the strip, disabled while there is
    /// nowhere to go, so each keeps the place the reader learned.
    init(
        port: BrowserSidebarNavigationPort,
        capabilities: BrowserInteractionCapabilities,
        @ViewBuilder trailingAccessory: () -> TrailingAccessory = {
            EmptyView()
        }
    ) {
        self.port = port
        self.capabilities = capabilities
        self.trailingAccessory = trailingAccessory()
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The strip's width, which decides whether Forward fits.
    @State private var width: CGFloat = .infinity

    var body: some View {
        strip
            // Each control fades between enabled and disabled rather than
            // flipping, on another tab or Space too. Reload fades to stop on
            // its own.
            .contentTransition(.opacity)
            .animation(CrestMotion.controlState.unlessReducingMotion(reduceMotion), value: state)
            .labelStyle(.iconOnly)
            .buttonStyle(
                CrestChromeButtonStyle(controlSize: metrics.controlSize)
            )
            .padding(.leading, metrics.leadingInset)
            .padding(.trailing, metrics.trailingInset)
            .padding(.vertical, verticalPadding)
            .modifier(
                BrowserSidebarNavigationControlBand(
                    height: metrics.barHeight,
                    growsWithContent: metrics.growsWithContent
                )
            )
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }

    private var strip: some View {
        HStack(spacing: metrics.controlSpacing) {
            Spacer(minLength: metrics.leadingSpacerMinimum)

            BrowserSidebarNavigationHistoryControl(
                direction: .back,
                port: port,
                metrics: metrics
            )

            if showsForward {
                BrowserSidebarNavigationHistoryControl(
                    direction: .forward,
                    port: port,
                    metrics: metrics
                )
            }

            BrowserReloadControl(
                isLoading: port.isLoading(),
                isDeveloperMode: isDeveloperMode,
                reloadOrStop: port.reloadOrStop,
                reload: port.reload,
                reloadFromOrigin: port.reloadFromOrigin,
                clearCookiesAndReload: port.clearCookiesAndReload,
                isEnabled: port.hasActivePage(),
                reloadControlSize: metrics.controlSize,
                menuControlSize: metrics.reloadMenuControlSize,
                symbolPointSize: metrics.reloadSymbolPointSize
            )

            trailingAccessory
        }
    }

    /// Whether Forward fits beside the window's own controls. The developer
    /// reload menu beside reload asks for its room too.
    private var showsForward: Bool {
        guard let fold = metrics.forwardFoldWidth else { return true }
        let developerMenu = isDeveloperMode ? metrics.reloadMenuControlSize.width + metrics.controlSpacing : 0
        return width >= fold + developerMenu
    }

    private var isDeveloperMode: Bool {
        port.activeURL()?.isLocalDevelopmentAddress == true
    }

    /// Which controls are enabled: where history goes, and whether there is
    /// a page to reload.
    private var state: [Bool] {
        [port.canGoBack(), port.canGoForward(), port.hasActivePage()]
    }

    private var verticalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? metrics.accessibilityVerticalPadding
            : 0
    }

    private var metrics: BrowserSidebarNavigationControlMetrics {
        capabilities.navigationControlMetrics
    }
}
