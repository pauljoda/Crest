import Foundation
import WebKit

@MainActor
final class BrowserExtensionWindowAdapter: NSObject, WKWebExtensionWindow {
    let spaceID: SpaceID
    private weak var coordinator: BrowserExtensionTabWindowCoordinator?

    init(
        spaceID: SpaceID,
        coordinator: BrowserExtensionTabWindowCoordinator
    ) {
        self.spaceID = spaceID
        self.coordinator = coordinator
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        coordinator?.tabs(in: spaceID, context: context) ?? []
    }

    func activeTab(
        for context: WKWebExtensionContext
    ) -> (any WKWebExtensionTab)? {
        coordinator?.activeTab(in: spaceID, context: context)
    }

    func windowType(
        for context: WKWebExtensionContext
    ) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(
        for context: WKWebExtensionContext
    ) -> WKWebExtension.WindowState {
        geometry(for: context).state
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        false
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        geometry(for: context).frame
    }

    #if os(macOS)
    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        geometry(for: context).screenFrame
    }
    #endif

    func focus(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let coordinator,
            coordinator.owns(context: context, spaceID: spaceID)
        else {
            completionHandler(coordinator?.adapterError(.windowUnavailable))
            return
        }
        coordinator.focus(
            spaceID: spaceID,
            completionHandler: completionHandler
        )
    }

    func close(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        completionHandler(coordinator?.adapterError(.unsupportedOperation))
    }

    private func geometry(
        for context: WKWebExtensionContext
    ) -> BrowserExtensionWindowGeometry {
        guard let coordinator,
            coordinator.owns(context: context, spaceID: spaceID)
        else {
            return .unavailable
        }
        return coordinator.windowGeometry(for: spaceID)
    }
}
