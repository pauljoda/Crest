import SwiftUI

/// Marks a tab whose page plays sound, or plays it muted, and draws nothing
/// otherwise. Pressing the mark mutes the tab or unmutes it, without selecting
/// it, while the row may act.
struct BrowserSidebarTabAudioMark: View {
    // MARK: - Variables

    let tabID: UUID
    let context: BrowserSidebarListContext
    /// Whether the row drawing the mark may act now, asked when it is pressed.
    let canAct: () -> Bool

    var body: some View {
        if let audio = context.audio(of: tabID) {
            Button {
                if canAct() { context.toggleMute(of: tabID) }
            } label: {
                Image(systemName: audio.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(
                CrestChromeButtonStyle(
                    controlSize: CGSize(
                        width: BrowserSidebarTabMarkMetrics.controlSize,
                        height: BrowserSidebarTabMarkMetrics.controlSize))
            )
            .help(Text(audio.label))
            .accessibilityLabel(Text(audio.actionName))
            .accessibilityValue(Text(audio.label))
        }
    }
}
