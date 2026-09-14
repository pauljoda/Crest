import Foundation
import WebKit

extension BrowserExtensionTabWindowCoordinator {
    /// WebKit owns numeric API IDs. Broker requests carry the public window
    /// bounds instead; ambiguous matches are refused rather than guessed.
    func brokerWindow(in spaceID: SpaceID, message: [String: Any]) throws -> BrowserExtensionWindowAdapter? {
        let windows = hostWindowOrder.compactMap { windowsBySpace[spaceID]?[$0] }
        guard let descriptor = message["window"] as? [String: Any] else {
            guard windows.count > 1, message["tabIndex"] != nil else { return window(for: spaceID) }
            let target = try BrowserExtensionTabTarget(message: message)
            let matching = windows.filter { window in
                let state = brokerState(in: spaceID, window: window)
                return (try? target.resolve(in: state, liveTabs: Set(state.tabs.map(\.id)))) != nil
            }
            guard matching.count == 1 else { throw adapterError(.windowUnavailable) }
            return matching[0]
        }
        var candidates = windows.filter { matchesBrokerGeometry(descriptor, window: $0) }
        if candidates.count > 1, message["tabIndex"] != nil {
            let target = try BrowserExtensionTabTarget(message: message)
            candidates = candidates.filter { window in
                let state = brokerState(in: spaceID, window: window)
                return (try? target.resolve(in: state, liveTabs: Set(state.tabs.map(\.id)))) != nil
            }
        }
        guard candidates.count == 1 else { throw adapterError(.windowUnavailable) }
        return candidates[0]
    }

    func brokerState(in spaceID: SpaceID, window: BrowserExtensionWindowAdapter?) -> BrowserExtensionSpaceState {
        guard let window else { return currentState?.space(spaceID) ?? .init(id: spaceID, tabs: []) }
        let space = currentState?.space(spaceID)
        return .init(
            id: spaceID,
            tabs: ownedTabIDs(in: window).enumerated().compactMap { index, id in
                guard let tab = space?.tab(id) else { return nil }
                return .init(
                    id: tab.id, title: tab.title, url: tab.url, placement: tab.placement, index: index,
                    isSelected: tab.isSelected, isLoadingComplete: tab.isLoadingComplete,
                    isReaderModeActive: tab.isReaderModeActive)
            })
    }

    /// Native indices omit tabs currently hosted in other windows. Translate
    /// their insertion anchor back into the shared session's ordering.
    func sessionInsertionIndex(
        _ index: Int, in window: BrowserExtensionWindowAdapter?, excluding excluded: Set<TabID> = []
    ) -> Int {
        guard !hostWindows.isEmpty, let window,
            let space = host(for: window)?.browser?.session.space(id: window.spaceID)
        else { return index }
        return BrowserSession.extensionTabInsertionIndex(
            index, in: space.tabs, among: Set(ownedTabIDs(in: window)), excluding: excluded)
    }

    func brokerWindowDescriptor(_ window: BrowserExtensionWindowAdapter?) -> [String: Any]? {
        guard let window else { return hasRegisteredHostWindows ? ["unavailable": true] : nil }
        let geometry = windowGeometry(for: window)
        guard !geometry.frame.isNull, !geometry.frame.isInfinite else {
            return hasRegisteredHostWindows ? ["unavailable": true] : nil
        }
        let frame = geometry.frame
        #if os(macOS)
            let top = geometry.screenFrame.isNull ? frame.minY : geometry.screenFrame.maxY - frame.maxY
        #else
            let top = frame.minY
        #endif
        return [
            "left": frame.minX, "top": top, "alternateTop": frame.minY,
            "width": frame.width, "height": frame.height, "focused": window === reportedFocusedWindow,
        ]
    }

    private func matchesBrokerGeometry(_ descriptor: [String: Any], window: BrowserExtensionWindowAdapter) -> Bool {
        guard let expected = brokerWindowDescriptor(window) else { return false }
        for key in ["left", "width", "height"] {
            guard let received = descriptor[key] as? NSNumber, let value = expected[key] as? NSNumber,
                CFGetTypeID(received) != CFBooleanGetTypeID(), received.doubleValue.isFinite,
                abs(received.doubleValue - value.doubleValue) < 1
            else { return false }
        }
        guard let top = descriptor["top"] as? NSNumber, CFGetTypeID(top) != CFBooleanGetTypeID(),
            top.doubleValue.isFinite
        else { return false }
        return ["top", "alternateTop"].contains { key in
            guard let value = expected[key] as? NSNumber else { return false }
            return abs(top.doubleValue - value.doubleValue) < 1
        }
    }
}
