import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserUtilityPresentationState {
    static let selectedSurfaceDefaultsKey = "browser.utility.selected-surface"

    private(set) var surface: BrowserUtilitySurface?
    private(set) var isSwitcherExpanded = false
    private(set) var isSiteControlPresented = false
    private(set) var isSiteControlContextMenuPresented = false
    private(set) var triggerFrameInGlobal: CGRect?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let persistenceKey: String
    @ObservationIgnored private var lastSelectedSurface = BrowserUtilitySurface.archive

    init(
        defaults: UserDefaults? = nil,
        persistenceKey: String = selectedSurfaceDefaultsKey
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        if let rawValue = defaults?.string(forKey: persistenceKey),
            let persistedSurface = BrowserUtilitySurface(rawValue: rawValue)
        {
            lastSelectedSurface = persistedSurface
        }
    }

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
        lastSelectedSurface = surface
        defaults?.set(surface.rawValue, forKey: persistenceKey)
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

    func toggleSwitcher(hasNewDownloads: Bool = false) {
        if isSwitcherExpanded {
            dismiss()
        } else {
            present(hasNewDownloads ? .downloads : lastSelectedSurface)
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

enum BrowserUtilitySurface: String, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case archive
    case history
    case downloads

    var id: Self { self }
}
