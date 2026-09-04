import Foundation

enum BrowserExtensionSidebarBrokerError: LocalizedError, Equatable {
    case invalidRequest
    case staleTab
    case pathIconsOnly
    case userGesture(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "The extension supplied an invalid sidebar request."
        case .staleTab: "The sidebar target tab changed or is no longer available."
        case .pathIconsOnly: "sidebarAction.setIcon: Crest supports path icons only."
        case .userGesture(let api): "`\(api)()` may only be called in response to a user gesture."
        }
    }
}

/// The wire target deliberately contains no invented WebKit identifier. JS
/// resolves native IDs, then this decoder checks the primary session index and
/// URL again before accepting a native tab. Transient/auxiliary pages cannot be
/// addressed through this channel.
struct BrowserExtensionSidebarBrokerRequest {
    enum Operation: String, CaseIterable {
        case setOptions = "sidePanel.setOptions"
        case getOptions = "sidePanel.getOptions"
        case setBehavior = "sidePanel.setPanelBehavior"
        case getBehavior = "sidePanel.getPanelBehavior"
        case open = "sidePanel.open"
        case close = "sidePanel.close"
        case layout = "sidebar.layout"
        case setPanel = "sidebarAction.setPanel"
        case getPanel = "sidebarAction.getPanel"
        case setTitle = "sidebarAction.setTitle"
        case getTitle = "sidebarAction.getTitle"
        case setIcon = "sidebarAction.setIcon"
        case sidebarOpen = "sidebarAction.open"
        case sidebarClose = "sidebarAction.close"
        case sidebarToggle = "sidebarAction.toggle"
        case isOpen = "sidebarAction.isOpen"
    }

    private enum Target {
        case global
        case window
        case tab(index: Int, url: String?)
    }

    let operation: Operation
    private let target: Target
    let path: String?
    let enabled: Bool?
    let title: String?
    let clearsTitle: Bool
    let icon: BrowserExtensionSidebarIcon?
    let clearsIcon: Bool
    let openPanelOnActionClick: Bool?
    let userActivation: Bool

    var requiredCapability: String {
        operation.rawValue.hasPrefix("sidebarAction.") ? "sidebarAction" : "sidePanel"
    }

    var requiresUserGesture: Bool {
        [.open, .sidebarOpen, .sidebarClose, .sidebarToggle].contains(operation)
    }

    init(message: [String: Any]) throws {
        guard let api = message["api"] as? String, let operation = Operation(rawValue: api) else {
            throw BrowserExtensionSidebarBrokerError.invalidRequest
        }
        self.operation = operation
        userActivation = try Self.boolean(message, "userActivation") ?? false
        enabled = try Self.boolean(message, "enabled")
        openPanelOnActionClick = try Self.boolean(message, "openPanelOnActionClick")
        title = try Self.string(message, "title", allowsNull: operation == .setTitle)
        clearsTitle = message["title"] is NSNull
        if operation == .setTitle, message["title"] == nil { throw BrowserExtensionSidebarBrokerError.invalidRequest }
        if operation == .setPanel {
            guard message["panel"] != nil else { throw BrowserExtensionSidebarBrokerError.invalidRequest }
            path = try Self.string(message, "panel", allowsNull: true) ?? ""
        } else {
            path = try Self.string(message, "path")
        }
        if message["imageData"] != nil { throw BrowserExtensionSidebarBrokerError.pathIconsOnly }
        icon = operation == .setIcon ? path.map(BrowserExtensionSidebarIcon.packagePath) : nil
        clearsIcon = operation == .setIcon && (path == nil || path == "")

        switch operation {
        case .setOptions, .getOptions, .setPanel, .getPanel, .setTitle, .getTitle, .setIcon:
            guard let scope = message["scope"] as? [String: Any], let kind = scope["kind"] as? String else {
                throw BrowserExtensionSidebarBrokerError.invalidRequest
            }
            switch kind {
            case "default": target = .global
            case "window":
                guard operation != .setOptions && operation != .getOptions else {
                    throw BrowserExtensionSidebarBrokerError.invalidRequest
                }
                target = try Self.windowTarget(scope)
            case "tab": target = try Self.tabTarget(scope)
            default: throw BrowserExtensionSidebarBrokerError.invalidRequest
            }
        case .open, .close:
            target = message["tabIndex"] == nil ? try Self.windowTarget(message) : try Self.tabTarget(message)
        case .sidebarOpen, .sidebarClose, .sidebarToggle, .isOpen:
            target = try Self.windowTarget(message)
        case .setBehavior, .getBehavior, .layout:
            target = .global
        }
    }

    func resolveScope(in space: BrowserExtensionSpaceState, liveTabs: Set<TabID>) throws -> BrowserExtensionSidebarScope
    {
        switch target {
        case .global: return .default
        case .window: return .window
        case .tab(let index, let url):
            guard let tab = space.tabs.first(where: { $0.index == index }), liveTabs.contains(tab.id),
                url == nil || tab.url?.absoluteString == url
            else { throw BrowserExtensionSidebarBrokerError.staleTab }
            return .tab(tab.id)
        }
    }

    private static func windowTarget(_ value: [String: Any]) throws -> Target {
        guard value["windowKind"] as? String == "primary" else {
            throw BrowserExtensionSidebarBrokerError.invalidRequest
        }
        return .window
    }

    private static func tabTarget(_ value: [String: Any]) throws -> Target {
        _ = try windowTarget(value)
        guard let number = value["tabIndex"] as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
            number.doubleValue >= 0, number.doubleValue < Double(Int.max),
            number.doubleValue.rounded(.down) == number.doubleValue
        else { throw BrowserExtensionSidebarBrokerError.invalidRequest }
        return .tab(index: number.intValue, url: try string(value, "url"))
    }

    private static func string(_ value: [String: Any], _ key: String, allowsNull: Bool = false) throws -> String? {
        guard let raw = value[key] else { return nil }
        if allowsNull && raw is NSNull { return nil }
        guard let result = raw as? String else { throw BrowserExtensionSidebarBrokerError.invalidRequest }
        return result
    }

    private static func boolean(_ value: [String: Any], _ key: String) throws -> Bool? {
        guard let raw = value[key] else { return nil }
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw BrowserExtensionSidebarBrokerError.invalidRequest
        }
        return number.boolValue
    }
}
