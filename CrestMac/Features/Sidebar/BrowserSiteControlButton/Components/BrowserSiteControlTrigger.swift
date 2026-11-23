import SwiftUI

struct BrowserSiteControlTrigger: View {
    @Binding var isPresented: Bool
    let blockedPopupNotice: BrowserBlockedPopupNotice?
    /// Whether a permission request waits on the person, which the dot
    /// shows as a blocked pop-up does.
    var waitsOnPermission = false

    /// Whether something waits on the person under Site Controls' actions.
    private var waits: Bool {
        waitsOnPermission || blockedPopupNotice?.status.offersAllow == true
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "slider.horizontal.3")
                    .font(
                        .system(
                            size: BrowserTabTrailingControlMetrics.pointer.glyphSize,
                            weight: .medium
                        )
                    )
                if waits {
                    Circle()
                        .fill(CrestColor.warning)
                        .frame(width: 7, height: 7)
                        .overlay {
                            Circle().stroke(.background, lineWidth: 1)
                        }
                        .offset(x: 2, y: -1)
                        .accessibilityHidden(true)
                }
            }
            .frame(
                width: BrowserSiteControlMetrics.triggerSize.width,
                height: BrowserSiteControlMetrics.triggerSize.height
            )
            .contentShape(.rect)
        }
        .buttonStyle(
            CrestChromeButtonStyle(
                controlSize: BrowserSiteControlMetrics.triggerSize
            )
        )
        .foregroundStyle(waits ? CrestColor.warning : Color.secondary)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("browser-site-controls")
        .help(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if waitsOnPermission { return String(localized: "Site Controls, permission request waiting") }
        guard let blockedPopupNotice else { return "Site Controls" }
        return blockedPopupNotice.chromeAccessibilityLabel(
            surfaceName: "Site Controls"
        )
    }

    private var accessibilityHint: String {
        guard !waitsOnPermission, blockedPopupNotice != nil else {
            return "Opens controls for this website"
        }
        return "Opens the Automatic Pop-ups permission and retry guidance"
    }
}
