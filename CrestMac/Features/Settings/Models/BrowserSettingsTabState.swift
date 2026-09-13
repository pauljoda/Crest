import Observation
import SwiftUI

@Observable @MainActor
final class BrowserSettingsTabState {
    var navigation = BrowserSettingsNavigationState()
    let selections = BrowserSettingsSelections()
    var featureFilter = BrowserWebKitFeatureFlagFilter()
    var selectedSpaceID: SpaceID?
    var spaceEditorSection = BrowserSpaceEditorSection.appearance
    var spaceRouteRevision = 0
    var shortcutScrollRevision = 0
    let sidebarScroll = BrowserNativeScrollState()
    private(set) var consumedRouteRevision = 0
    @ObservationIgnored private var paneScrollStates: [BrowserSettingsDestination: BrowserNativeScrollState] = [:]
    @ObservationIgnored private var spaceScrollStates:
        [SpaceID: [BrowserSpaceEditorSection: BrowserNativeScrollState]] = [:]
    @ObservationIgnored private var shortcuts: BrowserShortcutSettingsModel?

    func retainShortcuts(_ initial: BrowserShortcutSettingsModel) -> BrowserShortcutSettingsModel {
        if let shortcuts { return shortcuts }
        shortcuts = initial
        return initial
    }

    func scroll(for spaceID: SpaceID, section: BrowserSpaceEditorSection) -> BrowserNativeScrollState {
        if let state = spaceScrollStates[spaceID]?[section] { return state }
        let state = BrowserNativeScrollState()
        spaceScrollStates[spaceID, default: [:]][section] = state
        return state
    }

    func scroll(for destination: BrowserSettingsDestination) -> BrowserNativeScrollState {
        if let state = paneScrollStates[destination] { return state }
        let state = BrowserNativeScrollState()
        paneScrollStates[destination] = state
        return state
    }

    func applyExternalRoute(_ destination: BrowserSettingsDestination, revision: Int) {
        guard revision > consumedRouteRevision else { return }
        consumedRouteRevision = revision
        navigation.applyExternalRoute(destination, revision: revision)
    }
}

private struct BrowserSettingsTabStateKey: EnvironmentKey {
    static let defaultValue: BrowserSettingsTabState? = nil
}

extension EnvironmentValues {
    var browserSettingsTabState: BrowserSettingsTabState? {
        get { self[BrowserSettingsTabStateKey.self] }
        set { self[BrowserSettingsTabStateKey.self] = newValue }
    }
}
