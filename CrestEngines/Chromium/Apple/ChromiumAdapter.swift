#if CREST_CHROMIUM_HOST
import AppKit

@MainActor
final class ChromiumAdapter: CorePageRuntime {
    let displayName = "Chromium"
    let isolationMode = "isolated"
    let sessionDescription = "Tabs, Spaces and website data use separate Chromium test profiles."
    private let host: any CrestChromiumEngineHost
    @MainActor private struct Entry {
        let identity: [String: Any]
        var creation: CoreMessage
        var close: CoreMessage?
        let surface = BrowserWebHostView()
    }
    private var pages: [String: Entry] = [:]
    var send: ((String, [String: Any], CoreMessage?) -> Void)?
    init(host: any CrestChromiumEngineHost) {
        self.host = host
        host.setBrowserObserver { [weak self] values in
            MainActor.assumeIsolated { self?.send?("engine.adoption_requested", ChromiumInternalURL.presentedValues(values), nil) }
        }
    }
    var descriptor: Data {
        get throws {
            try CoreAdapterDescriptor.make(
                id: "engine", role: "engine", implementation: "crest.chromium.macos",
                supported: ["pages", "navigation", "internal-pages"],
                unverified: ["extensions", "popups", "before-unload", "downloads", "permissions", "workspace-profiles", "workspace-transfer", "profile-deletion"],
                limitations: ["Experimental native host; feature parity remains under validation."])
        }
    }
    func nativeView(pageID: String) -> NSView? {
        guard let entry = pages[pageID], let view = host.view(forPage: pageID) else { return nil }
        entry.surface.attach(view)
        return entry.surface
    }
    func preparePresentation(pageID: String, windowID: String) -> Bool {
        host.preparePage(pageID, forWindow: windowID)
    }
    func didAttach(pageID: String, windowID: String) { host.didAttachPage(pageID, window: windowID) }
    func didDetach(pageID: String) { host.didDetachPage(pageID) }
    func dispose() {
        for entry in pages.values { entry.surface.detach() }
        host.disposePages()
        pages.removeAll()
    }
    private func removePage(_ pageID: String) {
        pages.removeValue(forKey: pageID)?.surface.detach()
    }
    func prepareToQuit(_ completion: @escaping @MainActor (Bool) -> Void) {
        host.prepareToQuit { allowed in MainActor.assumeIsolated { completion(allowed) } }
    }
    func cancelQuitPreparation() { host.cancelQuitPreparation() }
    func handle(_ message: CoreMessage) {
        if message.type == "engine.dispose_all" {
            dispose()
            send?("engine.stopped", [:], message)
            return
        }
        if message.type == "engine.release_workspace", let workspace = message.payload["workspaceId"] as? String {
            let ids = pages.filter { $0.value.creation.payload["workspaceId"] as? String == workspace }.map(\.key)
            for id in ids { removePage(id) }
            host.disposePages(ids, windows: message.payload["windowIds"] as? [String] ?? [],
                releaseProfiles: message.payload["releaseProfiles"] as? [String] ?? [])
            send?("engine.workspace_released", ["workspaceId": workspace], message)
            return
        }
        if message.type == "engine.reject_adoption", let token = message.payload["adoptionId"] as? String {
            host.rejectAdoption(token)
            return
        }
        let p = message.payload
        guard let pageID = p["pageId"] as? String, let profileID = p["profileId"] as? String,
            let windowID = p["windowId"] as? String, let tabID = p["tabId"] as? String,
            let spaceID = p["spaceId"] as? String, let generation = p["generation"] as? String
        else { return }
        let identity: [String: Any] = ["pageId": pageID, "tabId": tabID, "spaceId": spaceID, "generation": generation]
        if message.type == "engine.reassign_page" {
            let reply = p.filter { ["workspaceId", "spaceId", "tabId", "profileId", "pageId", "generation"].contains($0.key) }
            guard var entry = pages[pageID], entry.close == nil,
                entry.creation.payload["workspaceId"] as? String == p["sourceWorkspaceId"] as? String,
                entry.creation.payload["profileId"] as? String == profileID,
                entry.identity["tabId"] as? String == tabID, entry.identity["spaceId"] as? String == spaceID,
                entry.identity["generation"] as? String == generation,
                entry.surface.superview == nil,
                host.preparePage(pageID, forWindow: windowID)
            else { send?("engine.page_reassignment_failed", reply, message); return }
            entry.creation = message; pages[pageID] = entry
            send?("engine.page_reassigned", reply, message)
            return
        }
        if message.type == "engine.create_page" || message.type == "engine.adopt_page" {
            guard pages[pageID] == nil else { send?("engine.failed", identity, message); return }
            pages[pageID] = Entry(identity: identity, creation: message)
            let observer: (String, [String: Any]) -> Void = { [weak self] event, values in
                // The host contract invokes this block on Chromium's native UI thread.
                MainActor.assumeIsolated { self?.observe(pageID: pageID, event: event, values: values) }
            }
            let accepted: Bool
            if message.type == "engine.adopt_page", let token = p["adoptionId"] as? String {
                accepted = host.adoptPage(token, asPage: pageID, profile: profileID, observer: observer)
            } else {
                accepted = host.createPage(pageID, profile: profileID, window: windowID,
                    privateMode: p["profileMode"] as? String == "private",
                    sourceProfile: p["privateSourceProfileId"] as? String, observer: observer)
            }
            if !accepted {
                if let token = p["adoptionId"] as? String { host.rejectAdoption(token) }
                removePage(pageID)
                send?("engine.failed", identity, message)
            }
            return
        }
        guard let entry = pages[pageID], entry.identity["tabId"] as? String == tabID,
            entry.identity["spaceId"] as? String == spaceID, entry.identity["generation"] as? String == generation
        else { send?("engine.failed", identity, message); return }
        if message.type == "engine.close_page" { pages[pageID]?.close = message }
        if !host.command(message.type, page: pageID, url: (p["url"] as? String).map(ChromiumInternalURL.engine)) {
            pages[pageID]?.close = nil
            send?("engine.failed", identity, message)
        }
    }
    private func observe(pageID: String, event: String, values: [String: Any]) {
        guard let entry = pages[pageID] else { return }
        let values = ChromiumInternalURL.presentedValues(values)
        var payload = entry.identity
        switch event {
        case "created": send?("engine.page_created", payload, entry.creation)
        case "creation_failed":
            removePage(pageID)
            send?("engine.failed", payload, entry.creation)
        case "changed":
            for key in ["url", "title", "isLoading", "canGoBack", "canGoForward", "committed", "failure"] {
                if let value = values[key] { payload[key] = value }
            }
            send?("engine.page_changed", payload, nil)
        case "closed", "close_canceled":
            guard let close = entry.close else {
                if event == "closed" {
                    removePage(pageID)
                    send?("engine.page_destroyed", payload, nil)
                }
                return
            }
            if event == "closed" { removePage(pageID) }
            else { pages[pageID]?.close = nil }
            send?(event == "closed" ? "engine.page_closed" : "engine.close_canceled", payload, close)
        case "open_requested":
            guard let url = values["url"] as? String else { return }
            payload["url"] = url
            send?("engine.open_requested", payload, nil)
        default: break
        }
    }
}
#endif
