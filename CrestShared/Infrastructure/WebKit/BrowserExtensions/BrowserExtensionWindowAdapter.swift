import Foundation
import WebKit

@MainActor
final class BrowserExtensionWindowAdapter: NSObject, WKWebExtensionWindow {
    let spaceID: SpaceID
    let windowType: WKWebExtension.WindowType
    let isPrimary: Bool
    private weak var coordinator: BrowserExtensionTabWindowCoordinator?

    init(
        spaceID: SpaceID,
        windowType: WKWebExtension.WindowType = .normal,
        isPrimary: Bool = true,
        coordinator: BrowserExtensionTabWindowCoordinator
    ) {
        self.spaceID = spaceID
        self.windowType = windowType
        self.isPrimary = isPrimary
        self.coordinator = coordinator
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        coordinator?.tabs(in: self, context: context) ?? []
    }

    func activeTab(
        for context: WKWebExtensionContext
    ) -> (any WKWebExtensionTab)? {
        coordinator?.activeTab(in: self, context: context)
    }

    func windowType(
        for context: WKWebExtensionContext
    ) -> WKWebExtension.WindowType {
        windowType
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
            window: self,
            completionHandler: completionHandler
        )
    }

    func close(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let coordinator,
            coordinator.owns(context: context, spaceID: spaceID)
        else {
            completionHandler(coordinator?.adapterError(.windowUnavailable))
            return
        }
        coordinator.close(
            window: self,
            completionHandler: completionHandler
        )
    }

    private func geometry(
        for context: WKWebExtensionContext
    ) -> BrowserExtensionWindowGeometry {
        guard let coordinator,
            coordinator.owns(context: context, spaceID: spaceID)
        else {
            return .unavailable
        }
        return coordinator.windowGeometry(for: self)
    }
}
