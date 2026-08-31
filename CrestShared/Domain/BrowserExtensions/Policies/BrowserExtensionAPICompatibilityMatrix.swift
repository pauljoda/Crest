import Foundation

enum BrowserExtensionReferenceSupport: String, Sendable {
    case native
    case partial
    case unavailable
}

enum BrowserExtensionCrestRoute: String, Sendable {
    case native
    case nativePatched
    case emulated
    case unavailable
}

enum BrowserExtensionExecutionProcess: String, Hashable, Sendable {
    case background
    case extensionPage
    case contentScript
    case devtoolsPage
}

/// The extension runtime an installed package was authored and published for.
///
/// This is package provenance, not Crest pretending that its webpage engine is
/// Blink or Gecko. It lets extension-owned workers, pages, and isolated content
/// worlds make the same platform choice they make in the package's reference
/// browser instead of accidentally selecting Safari merely because WebKit is
/// the native substrate.
enum BrowserExtensionReferenceEnvironment: String, Sendable {
    case chromium
    case firefox
    case webKit
}

struct BrowserExtensionAPIContract: Sendable {
    let namespace: String
    let permissionNames: Set<String>
    let processes: Set<BrowserExtensionExecutionProcess>
    let chromium: BrowserExtensionReferenceSupport
    let firefox: BrowserExtensionReferenceSupport
    let webKit: BrowserExtensionReferenceSupport
    let crest: BrowserExtensionCrestRoute
    let usesCompatibilityRuntime: Bool
    let capabilityBrokerPermissions: Set<String>
    let hiddenWebKitAPIs: Set<String>
}

struct BrowserExtensionAPIMemberContract: Sendable {
    let path: String
    let processes: Set<BrowserExtensionExecutionProcess>
    let webKit: BrowserExtensionReferenceSupport
    let crest: BrowserExtensionCrestRoute
    let hidesWebKitMember: Bool
}

/// The browser contract Crest presents to portable WebExtensions.
///
/// Chromium and Firefox schemas describe the reference surface. WebKit's IDL
/// and the SDK installed with Xcode describe the native substrate. The route is
/// deliberately explicit so a new WebKit implementation cannot silently replace
/// a Crest implementation merely because a property changes from `undefined` to
/// present in a future OS release.
enum BrowserExtensionAPICompatibilityMatrix {
    static let chromiumRevision =
        "209681af9aaea48aa172a1a9eb1eb2cdc63c1e67"
    static let firefoxRevision =
        "5836a062726f715fda621338a17b51aff30d0a8c"
    static let webKitRevision =
        "e4856c6696f58bae6f5cf1e864d0550f9eff09f8"
    static let appleSDKBuild = "Xcode 27.0 (27A5237l), macOS 27.0 SDK"

    /// Every context value accepted by the pinned Chromium and Firefox menu
    /// schemas. Some values target browser chrome Crest does not present yet;
    /// accepting them still matters because one unsupported item must not
    /// invalidate an extension's complete menu replacement transaction.
    static let contextMenuContexts: Set<String> = [
        "action",
        "all",
        "audio",
        "bookmark",
        "browser_action",
        "editable",
        "frame",
        "image",
        "launcher",
        "link",
        "page",
        "page_action",
        "password",
        "selection",
        "tab",
        "tools_menu",
        "video",
    ]

    static let contracts: [BrowserExtensionAPIContract] = [
        contract("action", crest: .nativePatched, runtime: true),
        contract("alarms", crest: .nativePatched, runtime: true),
        contract(
            "bookmarks",
            permissions: ["bookmarks"],
            webKit: .unavailable,
            crest: .unavailable
        ),
        contract("browserAction", crest: .nativePatched, runtime: true),
        contract("commands", crest: .nativePatched, runtime: true),
        contract(
            "contextMenus",
            permissions: ["contextMenus", "menus"],
            crest: .nativePatched,
            runtime: true,
            broker: ["contextMenus", "menus"]
        ),
        contract("cookies", permissions: ["cookies"]),
        contract(
            "declarativeNetRequest",
            permissions: [
                "declarativeNetRequest",
                "declarativeNetRequestFeedback",
                "declarativeNetRequestWithHostAccess",
            ],
            webKit: .partial,
            crest: .native
        ),
        contract(
            "devtools",
            webKit: .partial,
            crest: .native,
            processes: [.devtoolsPage]
        ),
        contract(
            "dom",
            firefox: .unavailable,
            processes: [.extensionPage, .contentScript]
        ),
        contract(
            "downloads",
            permissions: ["downloads", "downloads.open"],
            webKit: .unavailable,
            crest: .emulated,
            runtime: true,
            broker: ["downloads"]
        ),
        contract(
            "extension",
            crest: .nativePatched,
            processes: [.background, .extensionPage, .contentScript],
            runtime: true
        ),
        contract(
            "history",
            permissions: ["history"],
            webKit: .unavailable,
            crest: .unavailable
        ),
        contract(
            "i18n",
            crest: .nativePatched,
            processes: [.background, .extensionPage, .contentScript],
            runtime: true
        ),
        contract(
            "identity",
            permissions: ["identity", "identity.email"],
            firefox: .partial,
            webKit: .unavailable,
            crest: .unavailable
        ),
        contract(
            "idle",
            permissions: ["idle"],
            webKit: .unavailable,
            crest: .emulated,
            runtime: true,
            broker: ["idle"]
        ),
        contract(
            "management",
            permissions: ["management"],
            webKit: .unavailable,
            crest: .emulated,
            runtime: true
        ),
        contract(
            "notifications",
            permissions: ["notifications"],
            webKit: .partial,
            crest: .emulated,
            runtime: true,
            broker: ["notifications"]
        ),
        contract(
            "offscreen",
            permissions: ["offscreen"],
            firefox: .unavailable,
            webKit: .unavailable,
            crest: .emulated,
            runtime: true,
            broker: ["offscreen"]
        ),
        contract(
            "omnibox",
            permissions: ["omnibox"],
            webKit: .unavailable,
            crest: .unavailable
        ),
        contract("pageAction"),
        contract(
            "permissions",
            permissions: ["permissions"],
            crest: .nativePatched,
            runtime: true
        ),
        contract(
            "privacy",
            permissions: ["privacy"],
            webKit: .unavailable,
            crest: .emulated,
            runtime: true
        ),
        contract(
            "runtime",
            crest: .nativePatched,
            processes: [.background, .extensionPage, .contentScript],
            runtime: true
        ),
        contract(
            "scripting",
            permissions: ["scripting"],
            crest: .nativePatched,
            runtime: true
        ),
        contract(
            "sessions",
            permissions: ["sessions"],
            webKit: .unavailable,
            crest: .unavailable
        ),
        contract(
            "sidePanel",
            permissions: ["sidePanel"],
            firefox: .unavailable,
            webKit: .partial,
            crest: .emulated,
            runtime: true
        ),
        contract(
            "sidebarAction",
            chromium: .unavailable,
            webKit: .partial,
            crest: .unavailable
        ),
        contract(
            "storage",
            permissions: ["storage", "unlimitedStorage"],
            crest: .nativePatched,
            processes: [.background, .extensionPage, .contentScript],
            runtime: true
        ),
        contract("tabs", permissions: ["tabs"], crest: .nativePatched),
        contract(
            "test",
            chromium: .unavailable,
            firefox: .unavailable,
            crest: .unavailable,
            processes: [.background, .extensionPage, .contentScript]
        ),
        contract(
            "topSites",
            permissions: ["topSites"],
            webKit: .unavailable,
            crest: .unavailable
        ),
        contract(
            "userScripts",
            permissions: ["userScripts"],
            webKit: .unavailable,
            crest: .unavailable
        ),
        contract(
            "webNavigation",
            permissions: ["webNavigation"],
            crest: .nativePatched,
            runtime: true
        ),
        contract(
            "webRequest",
            permissions: ["webRequest", "webRequestBlocking"],
            webKit: .partial,
            crest: .nativePatched,
            runtime: true
        ),
        contract("windows", crest: .nativePatched, runtime: true),
    ]

    /// Member-level routes for every API Crest currently changes or owns.
    ///
    /// A namespace can stay native while an individual dynamic member is
    /// hidden and replaced. This is the smallest routing unit WebKit exposes
    /// through `unsupportedAPIs`, and prevents no-op placeholders from
    /// accidentally advertising unsupported capabilities.
    static let members: [BrowserExtensionAPIMemberContract] = [
        member("action.getUserSettings", crest: .nativePatched),
        member("alarms.onAlarm", crest: .nativePatched),
        member("contextMenus.create", crest: .nativePatched),
        member("contextMenus.onClicked", crest: .nativePatched),
        member("contextMenus.remove", crest: .nativePatched),
        member("contextMenus.removeAll", crest: .nativePatched),
        member("contextMenus.update", crest: .nativePatched),
        member("browserAction.getUserSettings", crest: .nativePatched),
        member(
            "downloads.download",
            webKit: .unavailable,
            crest: .emulated
        ),
        member("extension.getBackgroundPage", crest: .nativePatched),
        member("extension.getViews", crest: .nativePatched),
        member(
            "i18n.getMessage",
            crest: .nativePatched,
            processes: [.background, .extensionPage, .contentScript]
        ),
        member("idle.onStateChanged", webKit: .unavailable, crest: .emulated),
        member("idle.queryState", webKit: .unavailable, crest: .emulated),
        member(
            "idle.setDetectionInterval",
            webKit: .unavailable,
            crest: .emulated
        ),
        member(
            "management.getSelf",
            webKit: .unavailable,
            crest: .emulated
        ),
        member(
            "offscreen.Reason",
            webKit: .unavailable,
            crest: .emulated
        ),
        member(
            "offscreen.closeDocument",
            webKit: .unavailable,
            crest: .emulated
        ),
        member(
            "offscreen.createDocument",
            webKit: .unavailable,
            crest: .emulated
        ),
        member(
            "offscreen.hasDocument",
            webKit: .unavailable,
            crest: .emulated
        ),
        member(
            "sidePanel.setPanelBehavior",
            webKit: .unavailable,
            crest: .emulated
        ),
        member(
            "management.getAll",
            webKit: .unavailable,
            crest: .unavailable
        ),
        member(
            "management.setEnabled",
            webKit: .unavailable,
            crest: .unavailable
        ),
        member(
            "notifications.create",
            webKit: .partial,
            crest: .emulated
        ),
        member(
            "notifications.clear",
            webKit: .partial,
            crest: .emulated
        ),
        member(
            "notifications.getAll",
            webKit: .partial,
            crest: .emulated
        ),
        member(
            "notifications.getPermissionLevel",
            webKit: .partial,
            crest: .emulated
        ),
        member(
            "notifications.update",
            webKit: .partial,
            crest: .emulated
        ),
        member(
            "notifications.onButtonClicked",
            webKit: .partial,
            crest: .emulated
        ),
        member(
            "notifications.onClicked",
            webKit: .partial,
            crest: .emulated
        ),
        member(
            "notifications.onClosed",
            webKit: .partial,
            crest: .emulated
        ),
        member("permissions.contains", crest: .nativePatched),
        member("permissions.getAll", crest: .nativePatched),
        member("permissions.remove", crest: .nativePatched),
        member("privacy.network", webKit: .unavailable, crest: .emulated),
        member("privacy.services", webKit: .unavailable, crest: .emulated),
        member("privacy.websites", webKit: .unavailable, crest: .emulated),
        member(
            "runtime.getManifest",
            crest: .nativePatched,
            processes: [.background, .extensionPage, .contentScript]
        ),
        member(
            "runtime.getURL",
            crest: .nativePatched,
            processes: [.background, .extensionPage, .contentScript]
        ),
        member(
            "runtime.onConnect",
            crest: .nativePatched,
            processes: [.background, .extensionPage, .contentScript]
        ),
        member(
            "runtime.onMessage",
            crest: .nativePatched,
            processes: [.background, .extensionPage, .contentScript]
        ),
        member("runtime.onUpdateAvailable", crest: .nativePatched),
        member("runtime.requestUpdateCheck", crest: .nativePatched),
        member("scripting.ExecutionWorld", crest: .nativePatched),
        member(
            "storage.local",
            crest: .nativePatched,
            processes: [.background, .extensionPage, .contentScript]
        ),
        member(
            "storage.managed",
            crest: .nativePatched,
            processes: [.background, .extensionPage, .contentScript]
        ),
        member(
            "storage.session",
            crest: .nativePatched,
            processes: [.background, .extensionPage, .contentScript]
        ),
        member(
            "storage.sync",
            crest: .nativePatched,
            processes: [.background, .extensionPage, .contentScript]
        ),
        member("tabs.get", crest: .nativePatched),
        member("tabs.query", crest: .nativePatched),
        member("tabs.sendMessage", crest: .nativePatched),
        member(
            "webNavigation.getAllFrames",
            crest: .nativePatched
        ),
        member(
            "webNavigation.onCreatedNavigationTarget",
            webKit: .unavailable,
            crest: .nativePatched
        ),
        member(
            "webNavigation.onHistoryStateUpdated",
            webKit: .unavailable,
            crest: .nativePatched
        ),
        member(
            "webNavigation.onReferenceFragmentUpdated",
            webKit: .unavailable,
            crest: .nativePatched
        ),
        member(
            "webNavigation.onTabReplaced",
            webKit: .unavailable,
            crest: .nativePatched
        ),
        member(
            "webRequest.handlerBehaviorChanged",
            webKit: .partial,
            crest: .nativePatched
        ),
        member(
            "webRequest.onAuthRequired",
            webKit: .partial,
            crest: .unavailable,
            hide: true
        ),
        member(
            "windows.create",
            crest: .nativePatched
        ),
        member("windows.update", crest: .nativePatched),
    ]

    static let compatibilityPermissionNames = Set(
        contracts.filter(\.usesCompatibilityRuntime)
            .flatMap(\.permissionNames)
    )

    static let availableNamespaceNames = contracts.filter {
        $0.crest != .unavailable
    }.map(\.namespace).sorted()

    static let namespaceRoutes = Dictionary(
        uniqueKeysWithValues: contracts.map {
            ($0.namespace, $0.crest.rawValue)
        }
    )

    static let memberRoutes = Dictionary(
        uniqueKeysWithValues: members.map {
            ($0.path, $0.crest.rawValue)
        }
    )

    static let namespaceProcesses = Dictionary(
        uniqueKeysWithValues: contracts.map {
            (
                $0.namespace,
                $0.processes.map(\.rawValue).sorted()
            )
        }
    )

    static let memberProcesses = Dictionary(
        uniqueKeysWithValues: members.map {
            (
                $0.path,
                $0.processes.map(\.rawValue).sorted()
            )
        }
    )

    static func capabilityBrokerGrantedPermissions(
        requestedPermissions: [String]
    ) -> Set<String> {
        let requested = Set(requestedPermissions)
        var granted = Set(
            contracts.flatMap(\.capabilityBrokerPermissions)
        ).intersection(requested)
        if granted.contains("menus") {
            granted.insert("contextMenus")
        }
        return granted
    }

    static func unsupportedWebKitAPIs(
        requestedPermissions: [String]
    ) -> Set<String> {
        let requested = Set(requestedPermissions)
        let applicableContracts = contracts.filter { contract in
            contract.permissionNames.isEmpty
                || !contract.permissionNames.isDisjoint(with: requested)
        }
        var unsupported = Set(
            applicableContracts.flatMap(\.hiddenWebKitAPIs)
        )
        for contract in applicableContracts
        where
            contract.webKit != .unavailable
            && (contract.crest == .emulated
                || contract.crest == .unavailable)
        {
            unsupported.insert("browser.\(contract.namespace)")
        }
        for member in members where member.hidesWebKitMember {
            unsupported.insert("browser.\(member.path)")
        }
        return unsupported
    }

    private static func contract(
        _ namespace: String,
        permissions: Set<String> = [],
        chromium: BrowserExtensionReferenceSupport = .native,
        firefox: BrowserExtensionReferenceSupport = .native,
        webKit: BrowserExtensionReferenceSupport = .native,
        crest: BrowserExtensionCrestRoute = .native,
        processes: Set<BrowserExtensionExecutionProcess> = [
            .background,
            .extensionPage,
        ],
        runtime: Bool = false,
        broker: Set<String> = [],
        hidden: Set<String> = []
    ) -> BrowserExtensionAPIContract {
        BrowserExtensionAPIContract(
            namespace: namespace,
            permissionNames: permissions,
            processes: processes,
            chromium: chromium,
            firefox: firefox,
            webKit: webKit,
            crest: crest,
            usesCompatibilityRuntime: runtime,
            capabilityBrokerPermissions: broker,
            hiddenWebKitAPIs: hidden
        )
    }

    private static func member(
        _ path: String,
        webKit: BrowserExtensionReferenceSupport = .native,
        crest: BrowserExtensionCrestRoute,
        processes: Set<BrowserExtensionExecutionProcess> = [
            .background,
            .extensionPage,
        ],
        hide: Bool = false
    ) -> BrowserExtensionAPIMemberContract {
        BrowserExtensionAPIMemberContract(
            path: path,
            processes: processes,
            webKit: webKit,
            crest: crest,
            hidesWebKitMember: hide
        )
    }
}
