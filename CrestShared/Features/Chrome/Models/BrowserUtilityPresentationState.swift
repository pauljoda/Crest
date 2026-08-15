import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserUtilityPresentationState {
    private(set) var surface: BrowserUtilitySurface?
    private(set) var isSwitcherExpanded = false
    private(set) var triggerFrameInGlobal: CGRect?

    func recordTriggerFrame(_ frame: CGRect) {
        guard frame != triggerFrameInGlobal else { return }
        triggerFrameInGlobal = frame
    }

    func present(_ surface: BrowserUtilitySurface) {
        self.surface = surface
        isSwitcherExpanded = true
    }

    func dismiss(_ surface: BrowserUtilitySurface) {
        guard self.surface == surface else { return }
        self.surface = nil
        isSwitcherExpanded = false
    }

    func dismiss() {
        surface = nil
        isSwitcherExpanded = false
    }

    func toggleSwitcher() {
        if isSwitcherExpanded {
            dismiss()
        } else {
            present(.archive)
        }
    }

    func handleInteraction(_ interactionSurface: BrowserUtilityInteractionSurface) {
        switch interactionSurface {
        case .webContent, .sidebarBlankSpace:
            dismiss()
        case .control:
            break
        }
    }
}
