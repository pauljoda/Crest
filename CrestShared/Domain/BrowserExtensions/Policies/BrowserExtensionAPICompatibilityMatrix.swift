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
    /// Crest supplies the member so feature detection succeeds, but nothing
    /// can deliver it.
    ///
    /// This is not a patch and not an emulation: the object exists, accepts
    /// listeners, and reports them back honestly, while warning once that no
    /// event will ever arrive. Labelling these `nativePatched` claimed a
    /// behaviour Crest does not have. A native implementation still wins —
    /// the placeholder fills a gap rather than owning the contract.
    case presenceOnly
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
    let manifestKeys: Set<String>
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
    /// Removed from the namespace when the background is an MV3 service
    /// worker.
    ///
    /// Chrome exposes these DOM-window APIs to foreground extension pages
    /// only. WebKit also publishes them inside an MV3 worker, where their
    /// cross-context `Window` wrappers can outlive a popup and crash during
    /// reload. The axis is the background *environment*, not the process:
    /// a background *document* legitimately has them, so this cannot be
    /// expressed by dropping `.background` from `processes`.
    let hiddenInBackgroundWorker: Bool

    /// The namespace this member belongs to.
    var namespace: String {
        String(path.prefix { $0 != "." })
    }

    /// The member name without its namespace.
    var memberName: String {
        String(path.dropFirst(namespace.count + 1))
    }
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
    static let appleSDKBuild = "Xcode 27.0 (27A5252f), macOS 27.0 SDK"

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
        // WebKit trunk enabled a native `offscreen` API on 2026-08-28 behind
        // a pref that defaults on, so macOS 27 ships an implementation Crest
        // has never run an extension against. Recording it as `.partial`
        // rather than `.unavailable` is what makes `unsupportedWebKitAPIs`
        // hide `browser.offscreen` from the native surface, which in turn
        // keeps Crest's emulation — the one with a document lifecycle the
        // capability broker actually manages — the implementation packages
        // get, instead of it being silently displaced by an OS update.
        contract(
            "offscreen",
            permissions: ["offscreen"],
            firefox: .unavailable,
            webKit: .partial,
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
        // Publish the complete implemented surface together. Keep WebKit's
        // partial implementation hidden, including after its feature gate flips.
        contract(
            "sidePanel",
            permissions: ["sidePanel"],
            firefox: .unavailable,
            webKit: .partial,
            crest: .emulated,
            runtime: true,
            broker: ["sidePanel"]
        ),
        contract(
            "sidebarAction",
            chromium: .unavailable,
            webKit: .partial,
            crest: .emulated,
            runtime: true,
            manifestKeys: ["sidebar_action"]
        ),
        contract(
            "storage",
            permissions: ["storage", "unlimitedStorage"],
            crest: .nativePatched,
            processes: [.background, .extensionPage, .contentScript],
            runtime: true
        ),
        // WebKit has no tab-group surface at all — not a partial one — so
        // nothing here displaces a native implementation and nothing needs
        // hiding from `unsupportedWebKitAPIs`. Crest backs the namespace with
        // a real Space-scoped registry; what it does not have is a *drawn*
        // group, which is why `move` refuses and `onMoved` never fires.
        contract(
            "tabGroups",
            permissions: ["tabGroups"],
            webKit: .unavailable,
            crest: .emulated,
            runtime: true,
            broker: ["tabGroups"]
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

    /// The complete schema surface every `.emulated` namespace publishes.
    ///
    /// Chrome extensions feature-detect on the *namespace* and then use the
    /// schema in the same expression. A namespace object carrying only the
    /// members Crest implements is therefore worse than no namespace at all:
    /// the detection succeeds and the very next member access throws inside
    /// whatever awaited it, taking the rest of that bootstrap with it. So an
    /// emulated namespace exposes every member its reference schema defines.
    ///
    /// A member listed here that also has a row in `routedMembers` keeps that
    /// row and its real implementation. Every other one becomes a
    /// `presenceOnly` filler that fails honestly — a rejected promise, or
    /// `runtime.lastError` for the callback form — so this list is the single
    /// place a schema member is added to an emulated namespace.
    static let emulatedSurface: [String: [String]] = [
        "downloads": [
            "download",
            "search",
            "pause",
            "resume",
            "cancel",
            "getFileIcon",
            "open",
            "show",
            "showDefaultFolder",
            "erase",
            "removeFile",
            "acceptDanger",
            "setShelfEnabled",
            "setUiOptions",
            "onCreated",
            "onErased",
            "onChanged",
            "onDeterminingFilename",
        ],
        "idle": [
            "queryState",
            "setDetectionInterval",
            "onStateChanged",
            "getAutoLockDelay",
        ],
        "management": [
            "getSelf",
            "getAll",
            "get",
            "getPermissionWarningsById",
            "getPermissionWarningsByManifest",
            "setEnabled",
            "uninstall",
            "uninstallSelf",
            "launchApp",
            "createAppShortcut",
            "setLaunchType",
            "generateAppForLink",
            "onInstalled",
            "onUninstalled",
            "onEnabled",
            "onDisabled",
        ],
        "notifications": [
            "create",
            "update",
            "clear",
            "getAll",
            "getPermissionLevel",
            "onClicked",
            "onButtonClicked",
            "onClosed",
            "onPermissionLevelChanged",
            "onShowSettings",
        ],
        "offscreen": [
            "createDocument",
            "closeDocument",
            "hasDocument",
            "Reason",
        ],
        "privacy": [
            "network",
            "services",
            "websites",
        ],
        "sidePanel": [
            "setOptions", "getOptions", "setPanelBehavior", "getPanelBehavior", "open", "close", "getLayout",
            "onOpened", "onClosed", "Side",
        ],
        "sidebarAction": [
            "setTitle", "getTitle", "setIcon", "setPanel", "getPanel", "open", "close", "toggle", "isOpen",
        ],
        // `TabGroup` is deliberately absent: Chromium declares it as a
        // dictionary type, and Chrome publishes no property for it. `Color`
        // and `TAB_GROUP_ID_NONE` are published, because Chrome does — the
        // official Claude extension dereferences `tabGroups.Color` in a
        // static class field, before its worker can do anything else.
        "tabGroups": [
            "get", "query", "update", "move", "onCreated", "onUpdated", "onMoved", "onRemoved",
            "Color", "TAB_GROUP_ID_NONE",
        ],
    ]

    /// Member-level routes for every API Crest currently changes or owns.
    ///
    /// A namespace can stay native while an individual dynamic member is
    /// hidden and replaced. This is the smallest routing unit WebKit exposes
    /// through `unsupportedAPIs`, and prevents no-op placeholders from
    /// accidentally advertising unsupported capabilities.
    ///
    /// Every member-level consumer reads `members`, which is this table plus
    /// the `presenceOnly` fillers `emulatedSurface` implies.
    private static let routedMembers: [BrowserExtensionAPIMemberContract] = [
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
        member(
            "extension.getBackgroundPage",
            crest: .nativePatched,
            hiddenInBackgroundWorker: true
        ),
        member(
            "extension.getViews",
            crest: .nativePatched,
            hiddenInBackgroundWorker: true
        ),
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
            webKit: .partial,
            crest: .emulated
        ),
        member(
            "offscreen.closeDocument",
            webKit: .partial,
            crest: .emulated
        ),
        member(
            "offscreen.createDocument",
            webKit: .partial,
            crest: .emulated
        ),
        member(
            "offscreen.hasDocument",
            webKit: .partial,
            crest: .emulated
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
        member("sidePanel.Side", webKit: .partial, crest: .emulated),
        member("sidePanel.setOptions", webKit: .partial, crest: .emulated),
        member("sidePanel.getOptions", webKit: .partial, crest: .emulated),
        member("sidePanel.setPanelBehavior", webKit: .partial, crest: .emulated),
        member("sidePanel.getPanelBehavior", webKit: .partial, crest: .emulated),
        member("sidePanel.open", webKit: .partial, crest: .emulated),
        member("sidePanel.close", webKit: .partial, crest: .emulated),
        member("sidePanel.getLayout", webKit: .partial, crest: .emulated),
        member("sidePanel.onOpened", webKit: .partial, crest: .emulated),
        member("sidePanel.onClosed", webKit: .partial, crest: .emulated),
        member("sidebarAction.setTitle", webKit: .partial, crest: .emulated),
        member("sidebarAction.getTitle", webKit: .partial, crest: .emulated),
        member("sidebarAction.setIcon", webKit: .partial, crest: .emulated),
        member("sidebarAction.setPanel", webKit: .partial, crest: .emulated),
        member("sidebarAction.getPanel", webKit: .partial, crest: .emulated),
        member("sidebarAction.open", webKit: .partial, crest: .emulated),
        member("sidebarAction.close", webKit: .partial, crest: .emulated),
        member("sidebarAction.toggle", webKit: .partial, crest: .emulated),
        member("sidebarAction.isOpen", webKit: .partial, crest: .emulated),
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
        // Every portable package reads its own identity from here, and the
        // compatibility runtime carries a stable value for it. Without a row
        // the routing filter drops that fallback before it is installed, so a
        // runtime that publishes no `id` leaves the package unable to name
        // itself. `nativePatched`: a runtime that does publish one keeps it.
        member(
            "runtime.id",
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
        // The callback-form sibling of `extension.getBackgroundPage`, and it
        // returns the same live `Window`. Chrome does not publish it to an MV3
        // worker either.
        member(
            "runtime.getBackgroundPage",
            crest: .nativePatched,
            processes: [.background, .extensionPage],
            hiddenInBackgroundWorker: true
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
        // Every executable member of the namespace. `tabGroups.onMoved` is
        // absent on purpose: Crest never reorders a group, so it becomes the
        // `presenceOnly` filler `emulatedSurface` implies — an event object
        // that keeps its listeners and says once that none of them will run.
        member("tabGroups.Color", webKit: .unavailable, crest: .emulated),
        member("tabGroups.TAB_GROUP_ID_NONE", webKit: .unavailable, crest: .emulated),
        member("tabGroups.get", webKit: .unavailable, crest: .emulated),
        member("tabGroups.query", webKit: .unavailable, crest: .emulated),
        member("tabGroups.update", webKit: .unavailable, crest: .emulated),
        // Implemented, and it refuses. A filler would reject with Crest's
        // generic text; this one rejects with Chromium's own
        // `kFailedToMoveGroupError` after validating the group id, which is
        // the failure a portable package is written to handle.
        member("tabGroups.move", webKit: .unavailable, crest: .emulated),
        member("tabGroups.onCreated", webKit: .unavailable, crest: .emulated),
        member("tabGroups.onUpdated", webKit: .unavailable, crest: .emulated),
        member("tabGroups.onRemoved", webKit: .unavailable, crest: .emulated),
        member("tabs.get", crest: .nativePatched),
        // Chromium schedules grouping under `chrome.tabs`, not `tabGroups`,
        // and gates it with the `tabs` permission. Crest keeps that split:
        // these two are the only way a group is ever created.
        member("tabs.group", webKit: .unavailable, crest: .emulated),
        member("tabs.ungroup", webKit: .unavailable, crest: .emulated),
        member("tabs.query", crest: .nativePatched),
        member("tabs.sendMessage", crest: .nativePatched),
        member(
            "webNavigation.getAllFrames",
            crest: .nativePatched
        ),
        // Nothing is patched here. Crest supplies an event object so a
        // portable package's feature detection succeeds, but it has no
        // navigation source that can fire it. `presenceOnly` says exactly
        // that; `nativePatched` claimed delivery Crest cannot perform.
        member(
            "webNavigation.onCreatedNavigationTarget",
            webKit: .unavailable,
            crest: .presenceOnly
        ),
        member(
            "webNavigation.onHistoryStateUpdated",
            webKit: .unavailable,
            crest: .presenceOnly
        ),
        member(
            "webNavigation.onReferenceFragmentUpdated",
            webKit: .unavailable,
            crest: .presenceOnly
        ),
        member(
            "webNavigation.onTabReplaced",
            webKit: .unavailable,
            crest: .presenceOnly
        ),
        member(
            "webRequest.handlerBehaviorChanged",
            webKit: .partial,
            crest: .nativePatched
        ),
        // The webRequest event surface. The runtime normalizes each of these
        // through one facade, and derives the list it walks from these rows so
        // a member the matrix hides — `onAuthRequired` — cannot be resurrected
        // by a literal list living beside the table that removed it.
        member("webRequest.onBeforeRequest", crest: .nativePatched),
        member("webRequest.onBeforeSendHeaders", crest: .nativePatched),
        member("webRequest.onSendHeaders", crest: .nativePatched),
        member("webRequest.onHeadersReceived", crest: .nativePatched),
        member(
            "webRequest.onAuthRequired",
            webKit: .partial,
            crest: .unavailable,
            hide: true
        ),
        member("webRequest.onBeforeRedirect", crest: .nativePatched),
        member("webRequest.onResponseStarted", crest: .nativePatched),
        member("webRequest.onCompleted", crest: .nativePatched),
        member("webRequest.onErrorOccurred", crest: .nativePatched),
        member(
            "webRequest.onActionIgnored",
            webKit: .unavailable,
            crest: .nativePatched
        ),
        member(
            "windows.create",
            crest: .nativePatched
        ),
        member("windows.update", crest: .nativePatched),
    ]

    /// The declared-but-unimplemented half of every emulated namespace.
    ///
    /// These rows exist so the surface is complete and the documentation says
    /// what each filler actually does. The WebKit column is inherited from the
    /// namespace contract rather than invented per member: the namespace is
    /// hidden from the native surface as a whole, so no member-level WebKit
    /// audit took place and claiming one would be worse than repeating what
    /// was reviewed.
    private static let emulatedSurfaceFillerMembers =
        emulatedSurfaceFillerMemberRows()

    private static func emulatedSurfaceFillerMemberRows()
        -> [BrowserExtensionAPIMemberContract]
    {
        let routedPaths = Set(routedMembers.map(\.path))
        let contractsByNamespace = Dictionary(
            uniqueKeysWithValues: contracts.map { ($0.namespace, $0) }
        )
        return emulatedSurface.keys.sorted().flatMap { namespace in
            guard
                let contract = contractsByNamespace[namespace],
                contract.crest == .emulated
            else { return [BrowserExtensionAPIMemberContract]() }
            return (emulatedSurface[namespace] ?? []).compactMap { name in
                let path = "\(namespace).\(name)"
                guard !routedPaths.contains(path) else { return nil }
                return member(
                    path,
                    webKit: contract.webKit,
                    crest: .presenceOnly,
                    processes: contract.processes
                )
            }
        }
    }

    /// Every member-level route, stated or implied.
    static let members: [BrowserExtensionAPIMemberContract] =
        routedMembers + emulatedSurfaceFillerMembers

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

    /// Namespaces Chrome exposes without regard to the manifest, even though
    /// the matrix records a permission name for them.
    ///
    /// `chrome.tabs` is always defined; the `tabs` permission widens the
    /// fields a tab object carries rather than gating the namespace. There is
    /// no `permissions` manifest permission at all — the entry in `contracts`
    /// names the namespace, not a declaration an extension can make.
    private static let unconditionallyExposedNamespaces: Set<String> = [
        "permissions",
        "tabs",
    ]

    /// The manifest permissions that gate each namespace's *exposure*.
    ///
    /// Chrome defines `chrome.<namespace>` only when the package declared one
    /// of these permissions, and feature detection is how portable extensions
    /// decide whether a capability exists. Crest's capability broker grants
    /// only the permissions a package requested, so publishing an emulated
    /// namespace nobody asked for produces an API where every call fails —
    /// and, for the namespaces backed by a watch port, a reconnect the broker
    /// refuses forever.
    ///
    /// An empty list means the namespace is exposed unconditionally. Optional
    /// permissions count as declared: Chrome exposes the namespace before the
    /// grant and fails the individual calls until the user allows them.
    static let namespacePermissions: [String: [String]] = Dictionary(
        uniqueKeysWithValues: contracts.map { contract in
            (
                contract.namespace,
                unconditionallyExposedNamespaces.contains(contract.namespace)
                    ? []
                    : contract.permissionNames.sorted()
            )
        }
    )

    static let namespaceManifestKeys: [String: [String]] = Dictionary(
        uniqueKeysWithValues: contracts.map { ($0.namespace, $0.manifestKeys.sorted()) }
    )

    static func capabilityBrokerGrantedCapabilities(manifest: [String: Any]) -> Set<String> {
        manifest["sidebar_action"] is [String: Any] ? ["sidebarAction"] : []
    }

    static let memberRoutes = Dictionary(
        uniqueKeysWithValues: members.map {
            ($0.path, $0.crest.rawValue)
        }
    )

    /// Every event member each namespace publishes, minus the ones Crest
    /// removes from the surface.
    ///
    /// The compatibility runtime walks this list when it normalizes a
    /// namespace's events. Deriving it here is what keeps a hidden member
    /// hidden: `webRequest.onAuthRequired` is marked `hide` in `members`, and
    /// a literal list in the runtime used to re-add the very event the matrix
    /// had just removed from WebKit's surface. Declaration order is preserved
    /// so the generated script stays stable across builds.
    static let namespaceEventMembers: [String: [String]] = {
        var result: [String: [String]] = [:]
        for member in members
        where
            member.memberName.hasPrefix("on")
            && !member.hidesWebKitMember
            && member.crest != .unavailable
        {
            result[member.namespace, default: []].append(member.memberName)
        }
        return result
    }()

    /// Members the runtime removes from their namespace when the prepared
    /// background is an MV3 service worker, keyed by namespace.
    static let backgroundWorkerHiddenMembers: [String: [String]] = {
        var result: [String: [String]] = [:]
        for member in members where member.hiddenInBackgroundWorker {
            result[member.namespace, default: []].append(member.memberName)
        }
        return result
    }()

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
        hidden: Set<String> = [],
        manifestKeys: Set<String> = []
    ) -> BrowserExtensionAPIContract {
        BrowserExtensionAPIContract(
            namespace: namespace,
            permissionNames: permissions,
            manifestKeys: manifestKeys,
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
        hide: Bool = false,
        hiddenInBackgroundWorker: Bool = false
    ) -> BrowserExtensionAPIMemberContract {
        BrowserExtensionAPIMemberContract(
            path: path,
            processes: processes,
            webKit: webKit,
            crest: crest,
            hidesWebKitMember: hide,
            hiddenInBackgroundWorker: hiddenInBackgroundWorker
        )
    }
}
