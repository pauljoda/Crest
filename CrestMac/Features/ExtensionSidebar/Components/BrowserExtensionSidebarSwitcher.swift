import SwiftUI

/// The side-panel header's extension switcher.
///
/// The rows are real `NSMenuItem`s. A SwiftUI `Menu` drops the image out of a
/// checked row's `Label` on macOS, which left the menu reading as a bare list
/// of names; an `NSMenuItem` carries the extension's own icon, its name, and
/// the checkmark on the presented panel together. The trigger itself stays
/// SwiftUI so the header keeps Crest's type and hover treatment instead of a
/// stock pop-up bezel.
struct BrowserExtensionSidebarSwitcher: View {
    let host: BrowserExtensionSidebarHost
    let panel: BrowserExtensionSidebarPanel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presenter = BrowserExtensionSidebarSwitcherPresenter()
    @State private var isHovering = false
    @State private var isPresenting = false

    var body: some View {
        Button(action: present) {
            HStack(spacing: CrestSpacing.extraExtraSmall) {
                Text(verbatim: panel.title).font(.callout).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, CrestSpacing.extraSmall)
            .frame(minHeight: CrestLayout.minimumHitTarget)
            .contentShape(.rect(cornerRadius: CrestRadius.compact))
        }
        .buttonStyle(BrowserExtensionSidebarSwitcherButtonStyle(isHovering: isHovering, isPresenting: isPresenting))
        .fixedSize(horizontal: false, vertical: true)
        .onHover { isHovering = $0 }
        .animation(
            BrowserVisualAccessibilityPolicy.animation(CrestMotion.surface, reduceMotion: reduceMotion),
            value: isHovering
        )
        .overlay {
            BrowserExtensionSidebarSwitcherMenuAnchor(
                presenter: presenter,
                makeModel: menuModel,
                select: select,
                presentingChanged: { isPresenting = $0 },
                hoverChanged: { isHovering = $0 }
            )
        }
        .accessibilityLabel("Choose Extension Side Panel")
        .accessibilityValue(Text(verbatim: panel.title))
        .help("Choose Extension Side Panel")
    }

    /// Keyboard and VoiceOver activation open the same menu the pointer does.
    private func present() {
        presenter.present?()
    }

    private func menuModel() -> BrowserExtensionSidebarSwitcherMenuModel {
        BrowserExtensionSidebarSwitcherMenuModel(
            panels: host.availablePanels,
            currentClientID: host.panel?.clientID,
            icon: { host.icon(for: $0) }
        )
    }

    private func select(_ clientID: BrowserExtensionServiceClientID) {
        guard let candidate = host.availablePanels.first(where: { $0.clientID == clientID }) else { return }
        host.select(candidate)
    }
}

/// Matches the header's close button: a borderless control that only shows a
/// wash while the pointer rests on it or while its menu is open.
private struct BrowserExtensionSidebarSwitcherButtonStyle: ButtonStyle {
    let isHovering: Bool
    let isPresenting: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                .primary.opacity(highlight(isPressed: configuration.isPressed)),
                in: .rect(cornerRadius: CrestRadius.compact)
            )
    }

    private func highlight(isPressed: Bool) -> Double {
        if isPressed || isPresenting { return CrestOpacity.interactionSelection }
        return isHovering ? CrestOpacity.hover : 0
    }
}
