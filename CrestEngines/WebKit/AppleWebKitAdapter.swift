import Foundation
import Observation
import WebKit

/// Retains Crest's existing BrowserPage, navigation delegates, dialogs, text input, and page mechanics.
@MainActor
final class AppleWebKitAdapter: CorePageRuntime {
    let displayName = "WebKit"
    private final class NativeRoute { var pageID: String? }
    private struct PendingPopup {
        let page: BrowserPlatformPage
        let route: NativeRoute
        let profileID: String
        let workspaceID: String?
        var closed = false
    }
    private var pendingPopups: [String: PendingPopup] = [:]
    private struct Entry {
        let page: BrowserPlatformPage
        let identity: [String: Any]
        var creation: CoreMessage
        let route: NativeRoute
        var committedCount: Int = 0
    }
    private var entries: [String: Entry] = [:]
    private var profiles: [String: WKWebsiteDataStore] = [:]
    private struct RetainedPageState {
        let data: Data
        let url: URL
        let profileID: String
        let workspaceID: String?
    }
    private var retainedStates: [String: RetainedPageState] = [:]
    private var contentPolicies: [String: BrowserContentBlockingPolicy] = [:]
    private var compiledContentRules: [WKContentRuleList] = []
    private var contentRulePreparation: Task<[WKContentRuleList], Error>?
    private let permissions = BrowserSitePermissionCenter()
    #if os(macOS)
        private let dialogs = BrowserDialogPresenter()
    #endif
    private let downloads = BrowserDownloadCenter(allowsCredentialSaving: false)
    var send: ((String, [String: Any], CoreMessage?) -> Void)?

    var descriptor: Data {
        get throws {
            try CoreAdapterDescriptor.make(
                id: "engine", role: "engine", implementation: "crest.webkit.\(CoreAdapterDescriptor.platform)",
                supported: ["pages", "navigation", "popups", "workspace-profiles", "profile-deletion", "workspace-transfer", "content-blocking", "page-residency"],
                unverified: ["before-unload", "downloads", "permissions"],
                unavailable: ["extensions"],
                limitations: ["Core adapter parity is incomplete; existing WebKit implementation is retained."])
        }
    }
    func nativeView(pageID: String) -> CoreNativePageView? { entries[pageID]?.page.webView }
    func dispose() {
        for entry in entries.values {
            entry.page.stopLoading()
            entry.page.prepareForSpaceDeletion()
            entry.page.pageEngine.nativeView.removeFromSuperview()
        }
        for popup in pendingPopups.values { popup.page.prepareForSpaceDeletion() }
        pendingPopups.removeAll()
        entries.removeAll()
        profiles.removeAll()
        retainedStates.removeAll()
        contentPolicies.removeAll()
    }
    func handle(_ message: CoreMessage) {
        let p = message.payload
        if message.type == "engine.dispose_all" {
            dispose()
            send?("engine.stopped", [:], message)
            return
        }
        if message.type == "engine.apply_content_blocking", let profile = p["profileId"] as? String,
            let raw = p["policy"] as? String, let policy = BrowserContentBlockingPolicy(rawValue: raw) {
            contentPolicies[profile] = policy
            let identity = p.filter { ["workspaceId", "spaceId", "profileId"].contains($0.key) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    if contentPolicies[profile] == .balanced { try await prepareContentRules() }
                    let current = contentPolicies[profile] ?? policy
                    for entry in entries.values where entry.creation.payload["profileId"] as? String == profile {
                        entry.page.applyContentBlocking(policy: current, balancedRuleLists: compiledContentRules)
                    }
                    for popup in pendingPopups.values where popup.profileID == profile {
                        popup.page.applyContentBlocking(policy: current, balancedRuleLists: compiledContentRules)
                    }
                    send?("engine.content_blocking_applied", identity, message)
                } catch { send?("engine.content_blocking_failed", identity, message) }
            }
            return
        }
        if message.type == "engine.delete_profile", let profile = p["profileId"] as? String {
            retainedStates = retainedStates.filter { $0.value.profileID != profile }
            for (id, entry) in entries where entry.creation.payload["profileId"] as? String == profile {
                entry.route.pageID = nil
                entry.page.stopLoading(); entry.page.prepareForSpaceDeletion(); entry.page.pageEngine.nativeView.removeFromSuperview()
                entries.removeValue(forKey: id)
            }
            for (id, popup) in pendingPopups where popup.profileID == profile {
                popup.route.pageID = nil
                popup.page.stopLoading(); popup.page.prepareForSpaceDeletion(); pendingPopups.removeValue(forKey: id)
            }
            let identity = p.filter { ["workspaceId", "spaceId", "profileId"].contains($0.key) }
            contentPolicies.removeValue(forKey: profile)
            guard let data = profiles.removeValue(forKey: profile) else {
                send?("engine.profile_deleted", identity, message); return
            }
            data.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
                self?.send?("engine.profile_deleted", identity, message)
            }
            return
        }
        if message.type == "engine.reassign_page", let pageID = p["pageId"] as? String {
            let identity = p.filter { ["workspaceId", "spaceId", "tabId", "profileId", "pageId", "generation"].contains($0.key) }
            guard var entry = entries[pageID],
                entry.creation.payload["workspaceId"] as? String == p["sourceWorkspaceId"] as? String,
                entry.creation.payload["profileId"] as? String == p["profileId"] as? String,
                entry.identity["tabId"] as? String == p["tabId"] as? String,
                entry.identity["spaceId"] as? String == p["spaceId"] as? String,
                entry.identity["generation"] as? String == p["generation"] as? String,
                entry.page.pageEngine.nativeView.superview == nil
            else { send?("engine.page_reassignment_failed", identity, message); return }
            entry.creation = message
            entries[pageID] = entry
            send?("engine.page_reassigned", identity, message)
            return
        }
        if message.type == "engine.release_workspace", let workspace = p["workspaceId"] as? String {
            retainedStates = retainedStates.filter { $0.value.workspaceID != workspace }
            for (id, entry) in entries where entry.creation.payload["workspaceId"] as? String == workspace {
                entry.page.stopLoading(); entry.page.prepareForSpaceDeletion(); entry.page.pageEngine.nativeView.removeFromSuperview()
                entries.removeValue(forKey: id)
            }
            for (id, popup) in pendingPopups where popup.workspaceID == workspace {
                popup.page.stopLoading(); popup.page.prepareForSpaceDeletion(); pendingPopups.removeValue(forKey: id)
            }
            for profile in p["releaseProfiles"] as? [String] ?? [] {
                profiles.removeValue(forKey: profile); contentPolicies.removeValue(forKey: profile)
            }
            send?("engine.workspace_released", ["workspaceId": workspace], message)
            return
        }
        if message.type == "engine.reject_adoption" {
            if let id = p["adoptionId"] as? String, let popup = pendingPopups.removeValue(forKey: id) {
                popup.page.stopLoading(); popup.page.prepareForSpaceDeletion()
            }
            return
        }
        guard let pageID = p["pageId"] as? String, let tabID = p["tabId"] as? String,
            let spaceID = p["spaceId"] as? String, let spaceUUID = UUID(uuidString: spaceID), let tabUUID = UUID(uuidString: tabID),
            let profileID = p["profileId"] as? String, let profileUUID = UUID(uuidString: profileID),
            let generation = p["generation"] as? String
        else { return }
        let identity: [String: Any] = ["pageId": pageID, "tabId": tabID, "spaceId": spaceID, "generation": generation]
        if message.type == "engine.adopt_page" {
            guard let id = p["adoptionId"] as? String, let popup = pendingPopups[id],
                popup.profileID == profileID, popup.page.spaceID.rawValue == spaceUUID, entries[pageID] == nil else {
                send?("engine.failed", identity, message); return
            }
            pendingPopups.removeValue(forKey: id)
            popup.route.pageID = pageID
            let tab = BrowserTab(id: TabID(rawValue: tabUUID), title: "New tab", url: nil, placement: .current)
            #if os(macOS)
                popup.page.updateNavigationContext(tab: tab, automaticallyOpensPeek: false)
            #else
                popup.page.adopt(tabID: tab.id, tab: tab)
            #endif
            entries[pageID] = Entry(page: popup.page, identity: identity, creation: message, route: popup.route)
            send?("engine.page_created", identity, message)
            if popup.closed { closeWebContentInitiatedPage(popup.page) }
            else { publish(pageID); observe(pageID) }
            return
        }
        if message.type == "engine.create_page" {
            guard entries[pageID] == nil else {
                send?("engine.failed", identity, message)
                return
            }
            contentPolicies[profileID] = BrowserContentBlockingPolicy(rawValue: p["contentBlockingPolicy"] as? String ?? "balanced") ?? .balanced
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    if contentPolicies[profileID] == .balanced { try await prepareContentRules() }
                    let route = NativeRoute(); route.pageID = pageID
                    let page = makePage(spaceID: spaceUUID, profileID: profileUUID, tabID: tabUUID, route: route)
                    entries[pageID] = Entry(page: page, identity: identity, creation: message, route: route)
                    var result = identity
                    if let state = retainedStates.removeValue(forKey: tabID), state.profileID == profileID,
                        state.url.absoluteString == p["url"] as? String {
                        result["restored"] = page.restoreInteractionState(state.data, expecting: state.url)
                    }
                    send?("engine.page_created", result, message)
                    publish(pageID)
                    observe(pageID)
                } catch { send?("engine.failed", identity, message) }
            }
            return
        }
        guard let entry = entries[pageID], entry.identity["generation"] as? String == generation,
            entry.identity["tabId"] as? String == tabID,
            entry.identity["spaceId"] as? String == spaceID
        else {
            send?("engine.failed", identity, message)
            return
        }
        switch message.type {
        case "engine.unload_page":
            Task { @MainActor [weak self] in
                guard let self else { return }
                let decision = await entry.page.residencyDecision(isSelected: entry.page.pageEngine.nativeView.superview != nil)
                // A native page may have become active while WebKit checked media.
                guard entries[pageID]?.page === entry.page else { return }
                guard decision.allowsAutomaticUnload, entry.page.pageEngine.nativeView.superview == nil,
                    !entry.page.isLoading, !entry.page.wasOpenedAsPopup else {
                    send?("engine.unload_canceled", identity, message); return
                }
                if let data = entry.page.interactionState, let url = entry.page.url, data.count <= 4_194_304 {
                    // Opaque history stays native and memory-only. Bound the cache
                    // independently of the durable descriptor/checkpoint budget.
                    while retainedStates.values.reduce(data.count, { $0 + $1.data.count }) > 33_554_432,
                        let first = retainedStates.keys.sorted().first { retainedStates.removeValue(forKey: first) }
                    retainedStates[tabID] = RetainedPageState(data: data, url: url, profileID: profileID,
                        workspaceID: entry.creation.payload["workspaceId"] as? String)
                }
                entry.route.pageID = nil
                entries.removeValue(forKey: pageID)
                entry.page.stopLoading(); entry.page.prepareForSpaceDeletion()
                send?("engine.page_unloaded", identity, message)
            }
        case "engine.navigate":
            if let text = p["url"] as? String, let url = URL(string: text) { entry.page.load(url) }
        case "engine.back": entry.page.goBack()
        case "engine.forward": entry.page.goForward()
        case "engine.reload": entry.page.reload()
        case "engine.stop": entry.page.stopLoading()
        case "engine.close_page":
            retainedStates.removeValue(forKey: tabID)
            // BrowserPage's existing close path has no cancelable before-unload API.
            // This limitation is declared in registration until a native close continuation is integrated.
            entry.page.stopLoading()
            entry.page.prepareForSpaceDeletion()
            entry.page.pageEngine.nativeView.removeFromSuperview()
            entries.removeValue(forKey: pageID)
            send?("engine.page_closed", identity, message)
        default: send?("engine.failed", identity, message)
        }
    }
    private func prepareContentRules() async throws {
        if !compiledContentRules.isEmpty { return }
        if contentRulePreparation == nil {
            contentRulePreparation = Task { @MainActor in
                // Compiled rules have no browsing data, but still use this app's
                // cache rather than Crest's default rule-list store.
                let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true)
                let directory = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "CrestControlPlane")
                    .appendingPathComponent("ContentRules", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                guard let store = WKContentRuleListStore(url: directory) else { throw CocoaError(.fileWriteUnknown) }
                let lists = try await BrowserContentRuleListProvider(ruleListStore: store).balancedRuleLists()
                guard !lists.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                return lists
            }
        }
        do { compiledContentRules = try await contentRulePreparation!.value }
        catch { contentRulePreparation = nil; throw error }
    }
    private func makePage(spaceID: UUID, profileID: UUID, tabID: UUID, route: NativeRoute,
        adoptedConfiguration: WKWebViewConfiguration? = nil) -> BrowserPlatformPage {
        let key = profileID.uuidString.lowercased()
        let profile = profiles[key] ?? .nonPersistent(); profiles[key] = profile
        let lists = contentPolicies[key] == .off ? [] : compiledContentRules
        let tab = BrowserTab(id: TabID(rawValue: tabID), title: "New tab", url: nil, placement: .current)
        let open: (URL) -> Void = { [weak self, route] url in
            guard let pageID = route.pageID else { return }
            self?.requestOpen(url, pageID: pageID)
        }
        #if os(macOS)
            let configuration = adoptedConfiguration ?? BrowserPageConfiguration.make(
                for: BrowsingProfile(id: profileID), websiteDataStore: profile)
            let page = BrowserPage(configuration: configuration, dialogPresenter: dialogs,
                downloadCenter: downloads, permissionCenter: permissions, spaceID: SpaceID(rawValue: spaceID),
                profileID: profileID, spaceName: "Control Plane", contentRuleLists: lists, ownsUserContentController: adoptedConfiguration == nil,
                allowsCredentialAccess: false, isCredentialAccessEnabled: false,
                openNewTab: open, openModifiedLink: { request, _, _ in if let url = request.url { open(url) } },
                opensExternalURL: { _ in })
            page.updateNavigationContext(tab: tab, automaticallyOpensPeek: false)
        #else
            let space = BrowserSpace(id: SpaceID(rawValue: spaceID), profile: BrowsingProfile(id: profileID),
                name: "Control Plane", symbol: "globe", accent: .indigo, folders: [], tabs: [tab], selectedTabID: tab.id)
            let page = MobileBrowserPage(tab: tab, space: space, downloadCenter: downloads, permissionCenter: permissions,
                websiteDataStore: profile, adoptedConfiguration: adoptedConfiguration, contentRuleLists: lists,
                allowsCredentialAccess: false, isCredentialAccessEnabled: false, loadsInitialURL: false,
                openNewTab: open, openModifiedLink: { url, _, _ in open(url); return nil }, opensExternalURL: { _ in })
        #endif
        page.host = self
        if adoptedConfiguration != nil { page.markOpenedAsPopup() }
        return page
    }
    private func requestOpen(_ url: URL, pageID: String) {
        guard let entry = entries[pageID] else { return }
        var payload = entry.identity
        payload["url"] = url.absoluteString
        send?("engine.open_requested", payload, nil)
    }
    private func observe(_ pageID: String) {
        guard let entry = entries[pageID] else { return }
        withObservationTracking {
            _ = entry.page.url
            _ = entry.page.title
            _ = entry.page.isLoading
            _ = entry.page.canGoBack
            _ = entry.page.canGoForward
            _ = entry.page.committedNavigationCount
            _ = entry.page.navigationFailure
            #if os(macOS)
                _ = entry.page.webContentFailureMessage
            #else
                _ = entry.page.showsProcessFailure
            #endif
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.publish(pageID)
                self?.observe(pageID)
            }
        }
    }
    private func publish(_ pageID: String) {
        guard var entry = entries[pageID] else { return }
        let page = entry.page
        var p = entry.identity
        p["url"] = page.url?.absoluteString as Any? ?? NSNull()
        #if os(macOS)
            let title = page.title
            let processFailed = page.webContentFailureMessage != nil
        #else
            let title = page.title ?? ""
            let processFailed = page.showsProcessFailure
        #endif
        p["title"] = String((title.isEmpty ? page.url?.host() ?? "New tab" : title).prefix(4096))
        p["isLoading"] = page.isLoading
        p["canGoBack"] = page.canGoBack
        p["canGoForward"] = page.canGoForward
        let failure: String? =
            page.navigationFailure != nil
            ? "navigation_failed" : processFailed ? "renderer_terminated" : nil
        p["failure"] = failure as Any? ?? NSNull()
        p["committed"] = page.committedNavigationCount > entry.committedCount
        entry.committedCount = page.committedNavigationCount
        entries[pageID] = entry
        send?("engine.page_changed", p, nil)
    }
}

#if os(macOS)
    extension AppleWebKitAdapter: BrowserPageHosting {}
#else
    extension AppleWebKitAdapter: MobileBrowserPageHosting {}
#endif

extension AppleWebKitAdapter {
    func adoptPopupWebView(configuration: WKWebViewConfiguration, requestedURL: URL?,
        opener: BrowserPlatformPage, selecting: Bool) -> WKWebView? {
        guard pendingPopups.count < 128,
            entries.values.contains(where: { $0.page === opener }) || pendingPopups.values.contains(where: { $0.page === opener })
        else { return nil }
        let profileID = opener.profileID.uuidString.lowercased()
        guard configuration.websiteDataStore === profiles[profileID] else { return nil }
        let token = UUID().uuidString.lowercased(); let route = NativeRoute()
        let page = makePage(spaceID: opener.spaceID.rawValue, profileID: opener.profileID,
            tabID: UUID(), route: route, adoptedConfiguration: configuration)
        let workspaceID = entries.values.first(where: { $0.page === opener })?.creation.payload["workspaceId"] as? String
            ?? pendingPopups.values.first(where: { $0.page === opener })?.workspaceID
        pendingPopups[token] = PendingPopup(page: page, route: route, profileID: profileID, workspaceID: workspaceID)
        var payload: [String: Any] = ["adoptionId": token, "profileId": profileID,
            "url": requestedURL?.absoluteString ?? "about:blank", "foreground": selecting]
        if let workspaceID { payload["workspaceId"] = workspaceID }
        if let entry = entries.first(where: { $0.value.page === opener }) { payload["sourcePageId"] = entry.key }
        send?("engine.adoption_requested", payload, nil)
        // WebKit performs the original navigation after this callback returns.
        // The core later binds this exact page without issuing another load.
        return page.webView
    }
    func closeWebContentInitiatedPage(_ page: BrowserPlatformPage) {
        guard page.wasOpenedAsPopup else { return }
        if let pending = pendingPopups.first(where: { $0.value.page === page }) {
            pendingPopups[pending.key]?.closed = true
            return
        }
        guard let entry = entries.first(where: { $0.value.page === page }) else { return }
        Task { @MainActor [weak self] in
            guard let self, let current = entries[entry.key], current.page === page else { return }
            entries.removeValue(forKey: entry.key)
            page.stopLoading(); page.prepareForSpaceDeletion(); page.pageEngine.nativeView.removeFromSuperview()
            send?("engine.page_destroyed", current.identity, nil)
        }
    }
    func discardDownloadOnlyPage(_ page: BrowserPlatformPage) { closeWebContentInitiatedPage(page) }
    private func pageForMessage(_ message: WKScriptMessage) -> BrowserPlatformPage? {
        guard let view = message.webView else { return nil }
        return entries.values.first(where: { $0.page.webView === view })?.page
            ?? pendingPopups.values.first(where: { $0.page.webView === view })?.page
    }
    func routeGeolocationMessage(_ message: WKScriptMessage) { pageForMessage(message)?.receiveGeolocationMessage(message) }
    func routeBlockedPopupMessage(_ message: WKScriptMessage) { pageForMessage(message)?.receiveBlockedPopupMessage(message) }
    func routeMediaSessionMessage(_ message: WKScriptMessage) { pageForMessage(message)?.receiveMediaSessionMessage(message) }
    #if os(macOS)
        func routeHostedWebNotificationMessage(_ message: WKScriptMessage) { pageForMessage(message)?.receiveHostedWebNotificationMessage(message) }
        func navigatePopupInCurrentPage(_ request: URLRequest, opener: BrowserPage) -> Bool { false }
        func activateNotificationSourcePage(_ page: BrowserPage) { reveal(page) }
        func restorePictureInPictureSourcePage(_ page: BrowserPage) { reveal(page) }
        private func reveal(_ page: BrowserPage) {
            guard let entry = entries.values.first(where: { $0.page === page }) else { return }
            send?("engine.reveal_requested", entry.identity, nil)
        }
    #else
        func loadOpenedLink(_ registration: BrowserModifiedLinkRegistration, request: URLRequest, selecting: Bool) {
            guard let entry = entries.values.first(where: { $0.identity["tabId"] as? String == registration.tab.id.rawValue.uuidString.lowercased() }) else { return }
            entry.page.load(request)
        }
    #endif
}
