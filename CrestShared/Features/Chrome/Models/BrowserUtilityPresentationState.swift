import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserUtilityPresentationState {
    private(set) var surface: BrowserUtilitySurface?
    private(set) var isSwitcherExpanded = false
    private(set) var isSiteControlPresented = false
    private(set) var isSiteControlContextMenuPresented = false
    private(set) var triggerFrameInGlobal: CGRect?

    var isSiteControlInteractionActive: Bool {
        isSiteControlPresented || isSiteControlContextMenuPresented
    }

    var isSidebarInteractionActive: Bool {
        isSwitcherExpanded || isSiteControlInteractionActive
    }

    func recordTriggerFrame(_ frame: CGRect) {
        guard frame != triggerFrameInGlobal else { return }
        triggerFrameInGlobal = frame
    }

    func setSiteControlPresented(_ isPresented: Bool) {
        guard isPresented != isSiteControlPresented else { return }
        isSiteControlPresented = isPresented
    }

    func setSiteControlContextMenuPresented(_ isPresented: Bool) {
        guard isPresented != isSiteControlContextMenuPresented else { return }
        isSiteControlContextMenuPresented = isPresented
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

    func toggleSwitcher(preferredSurface: BrowserUtilitySurface = .archive) {
        if isSwitcherExpanded {
            dismiss()
        } else {
            present(preferredSurface)
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

enum BrowserUtilityInteractionSurface: Equatable, Sendable {
    case webContent
    case sidebarBlankSpace
    case control
}

enum BrowserUtilitySurface: CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case archive
    case history
    case downloads

    var id: Self { self }
}
