import AppKit
import Observation

/// One window's extension side panel.
///
/// A panel is a trailing column in the page row — the `.panel` slot the shared
/// split layout already reserves — and never a tab. It carries no session
/// membership, is not persisted and is not synced, so closing the window or
/// quitting leaves nothing behind. The engine owns the panel document; this
/// object owns only which panel the window is showing and how wide it is.
@Observable
@MainActor
final class BrowserExtensionSidePanelHost {
    struct Panel: Identifiable {
        /// The owning extension's identifier.
        let id: String
        let title: String
        let icon: NSImage?
        /// The engine's panel view. Mounted as-is; the host never reparents it.
        let view: NSView
        /// Tears the panel document down. Called only for a user dismissal —
        /// an engine-initiated one has already released it.
        let close: () -> Void
    }

    private(set) var panel: Panel?
    private(set) var width = BrowserSplitPanelLayoutMetrics.defaultWidth

    /// Shows `panel`, replacing whatever this window was showing. One panel at
    /// a time matches the engine, which keeps one entry per tab.
    func present(_ panel: Panel) {
        if let current = self.panel, current.id != panel.id { current.close() }
        self.panel = panel
    }

    /// The user closed the panel.
    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.close()
    }

    /// The panel document or its extension host went away. The engine has
    /// already released the document, so this only drops the card.
    func dismiss(_ extensionID: String) {
        guard panel?.id == extensionID else { return }
        panel = nil
    }

    func commitWidth(_ width: CGFloat) {
        self.width = BrowserSplitPanelLayoutMetrics.clampedWidth(width)
    }
}
