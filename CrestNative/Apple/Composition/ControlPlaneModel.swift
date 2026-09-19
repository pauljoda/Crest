import Foundation
import Observation
import SwiftUI
import LocalAuthentication

@Observable @MainActor
final class ControlPlaneModel {
    private(set) var snapshot: CoreSnapshot?
    private(set) var workspaces: [String: CoreSnapshot] = [:]
    private(set) var removedWindowIDs: Set<String> = []
    private(set) var surfaces: [String: [CoreNativePageView]] = [:]
    var error: String?
    private(set) var saveNeedsRetry = false
    private(set) var hasStopped = false
    private(set) var isPreparingShutdown = false
    @ObservationIgnored private var transport: CoreTransport?
    @ObservationIgnored private let engine: any CorePageRuntime
    var engineDisplayName: String { engine.displayName }
    var sessionDescription: String { engine.sessionDescription }
    @ObservationIgnored private var storage: CoreSessionStorage?
    @ObservationIgnored private var restorableWindowIDs: [String] = []
    @ObservationIgnored private var claimedWindowIDs: Set<String> = []
    @ObservationIgnored private var openedWindowIDs: Set<String> = []
    @ObservationIgnored private var workspaceRequests: [String: [String: Any]] = [:]
    @ObservationIgnored private var sceneTransientWindows: [String: Set<String>] = [:]
    private(set) var engineCapabilities: Set<String> = []
    private(set) var recordsRevision: UInt64 = 0
    private(set) var recordsByTabID: [String: CoreRecordsPage] = [:]
    @ObservationIgnored private var recordRequests: [String: String] = [:]
    @ObservationIgnored private var beganWindowRestoration = false
    @ObservationIgnored private var sceneWindowIDs: [String: String] = [:]
    @ObservationIgnored private var lastSequence: UInt64 = 0
    @ObservationIgnored private var projectionRevision: UInt64 = 0
    @ObservationIgnored private var snapshotTransfer: CoreChunkTransfer?
    @ObservationIgnored private var recordsTransfer: CoreChunkTransfer?
    @ObservationIgnored private var leases: [String: String] = [:]
    @ObservationIgnored private var surfaceOwners: [String: String] = [:]
    @ObservationIgnored private var authentication: (String, LAContext)?
    @ObservationIgnored private var memoryPressure: (any DispatchSourceMemoryPressure)?
    @ObservationIgnored private var nativePanes: [String: (CoreNativePaneState, CoreNativePageView)] = [:]
    @ObservationIgnored private var surfaceTabs: [String: [String]] = [:]
    @ObservationIgnored var onStopped: (() -> Void)?
    @ObservationIgnored var onShutdownBlocked: (() -> Void)?
    @ObservationIgnored var onCloseWindows: (([String]) -> Void)?

    init(engine adapter: any CorePageRuntime, persistsSession: Bool = true, storageDirectory: URL? = nil) {
        engine = adapter
        do {
            let descriptor = try adapter.descriptor
            let registration = try JSONSerialization.jsonObject(with: descriptor) as? [String: Any]
            let capabilities = registration?["capabilities"] as? [String: [String: Any]] ?? [:]
            engineCapabilities = Set(capabilities.compactMap { key, value in
                value["status"] as? String == "supported" && value["contractVersion"] as? Int == 1 ? key : nil
            })
            let storage = persistsSession ? try CoreSessionStorage(directory: storageDirectory) : nil
            let initialState = try storage?.load()
            self.storage = storage
            restorableWindowIDs = (initialState?["windows"] as? [[String: Any]] ?? []).compactMap {
                (($0["id"] as? [String: Any])?["rawValue"] as? String)?.lowercased()
            }
            for window in initialState?["windows"] as? [[String: Any]] ?? [] {
                if let scene = window["platformSceneId"] as? String,
                    let id = (window["id"] as? [String: Any])?["rawValue"] as? String {
                    sceneWindowIDs[scene] = id.lowercased()
                }
            }
            transport = try CoreTransport(
                adapters: [
                    CoreAdapterDescriptor.make(
                        id: "ui", role: "ui", implementation: "crest.swiftui.\(CoreAdapterDescriptor.platform)",
                        supported: ["projections"]),
                    descriptor,
                    CoreAdapterDescriptor.make(
                        id: "platform", role: "platform",
                        implementation: "crest.\(CoreAdapterDescriptor.nativeUI).surfaces",
                        supported: ["surfaces", "device-authentication"]),
                    CoreAdapterDescriptor.make(
                        id: "services", role: "services", implementation: "crest.apple.isolated-storage",
                        supported: ["session-storage", "space-data-deletion"]),
                ], initialState: initialState, persistsSession: persistsSession, isolationMode: adapter.isolationMode,
                receive: { [weak self] in self?.receive($0) }, failed: { [weak self] in self?.error = $0 },
                stopped: { [weak self] in
                    self?.engine.dispose()
                    self?.surfaces.removeAll()
                    self?.nativePanes.removeAll()
                    self?.hasStopped = true
                    self?.onStopped?()
                })
            adapter.send = { [weak self] type, payload, cause in
                self?.transport?.post(type: type, payload: payload, sender: "engine", cause: cause)
            }
            let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
            pressure.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let pressure = self.memoryPressure else { return }
                    self.reportMemoryPressure(critical: pressure.data.contains(.critical))
                }
            }
            pressure.resume(); memoryPressure = pressure
        } catch {
            self.error = "The control plane could not start. Existing saved state has been left intact: \(error)"
            self.hasStopped = true
        }
    }
    private func reportMemoryPressure(critical: Bool) {
        guard !isPreparingShutdown, !hasStopped else { return }
        transport?.post(type: "platform.memory_pressure", payload: [
            "level": critical ? "critical" : "warning",
            "platform": CoreAdapterDescriptor.platform == "macos" ? "desktop" : "mobile"
        ], sender: "platform")
    }
    func releaseInactivePages() {
        transport?.post(type: "core.release_inactive_pages", payload: [
            "level": "critical", "platform": CoreAdapterDescriptor.platform == "macos" ? "desktop" : "mobile"
        ])
    }
    func queryRecords(tabID: String, windowID: String, spaceID: String, kind: String, query: String, offset: Int) {
        let queryID = UUID().uuidString.lowercased()
        recordRequests[tabID] = queryID
        command("core.query_records", windowID: windowID,
            extra: ["spaceId": spaceID, "kind": kind, "queryId": queryID, "query": String(query.prefix(512)), "offset": offset])
    }
    func cancelRecords(tabID: String) {
        recordRequests.removeValue(forKey: tabID); recordsByTabID.removeValue(forKey: tabID)
    }
    func openWindow(_ id: String) {
        guard openedWindowIDs.insert(id).inserted else { return }
        if let request = workspaceRequests.removeValue(forKey: id) {
            transport?.post(type: "core.create_workspace", payload: request)
        } else { transport?.post(type: "core.open_window", payload: ["windowId": id]) }
    }
    func prepareWorkspaceWindow(from windowID: String, mode: String) -> String? {
        guard engineCapabilities.contains("workspace-profiles"), let workspace = workspace(for: windowID),
            let space = space(windowID), space.isLocked != true, space.isDeleting != true else { return nil }
        let id = UUID().uuidString.lowercased()
        workspaceRequests[id] = ["windowId": id, "sourceWorkspaceId": workspace.workspaceId, "spaceId": space.id, "mode": mode]
        return id
    }
    func openWorkspaceInScene(from windowID: String, ownerWindowID: String, mode: String) -> String? {
        guard let id = prepareWorkspaceWindow(from: windowID, mode: mode) else { return nil }
        sceneTransientWindows[ownerWindowID, default: []].insert(id)
        openWindow(id)
        return id
    }
    func claimWindowID(_ requested: String?, sceneID: String? = nil) -> String {
        let id: String
        if let sceneID, let restored = sceneWindowIDs[sceneID] {
            id = restored
        } else if let requested, UUID(uuidString: requested) != nil, !claimedWindowIDs.contains(requested.lowercased()) {
            id = requested.lowercased()
        } else if !beganWindowRestoration, let restored = restorableWindowIDs.first {
            id = restored
        } else { id = UUID().uuidString.lowercased() }
        beganWindowRestoration = true
        claimedWindowIDs.insert(id)
        restorableWindowIDs.removeAll { $0 == id }
        return id
    }
    func remainingWindowsToRestore() -> [String] {
        let ids = restorableWindowIDs
        restorableWindowIDs.removeAll()
        return ids
    }
    func closeWindow(_ id: String) {
        guard openedWindowIDs.remove(id) != nil else { return }
        let dependents = sceneTransientWindows.removeValue(forKey: id) ?? []
        for dependent in dependents { closeWindow(dependent) }
        for owner in sceneTransientWindows.keys { sceneTransientWindows[owner]?.remove(id) }
        claimedWindowIDs.remove(id)
        restorableWindowIDs.removeAll { $0 == id }
        sceneWindowIDs = sceneWindowIDs.filter { $0.value != id }
        surfaces[id]?.forEach { $0.removeFromSuperview() }
        for (page, owner) in surfaceOwners where owner == id { engine.didDetach(pageID: page) }
        surfaces.removeValue(forKey: id)
        surfaceTabs.removeValue(forKey: id)
        surfaceOwners = surfaceOwners.filter { $0.value != id }
        leases.removeValue(forKey: id)
        pendingAttachments.removeValue(forKey: id)
        transport?.post(type: "core.close_window", payload: ["windowId": id])
    }
    func bindScene(_ sceneID: String, windowID: String) {
        sceneWindowIDs[sceneID] = windowID
        transport?.post(type: "core.bind_window_scene", payload: ["windowId": windowID, "sceneId": sceneID])
    }
    func discardScene(_ sceneID: String) {
        if let windowID = sceneWindowIDs[sceneID] { closeWindow(windowID) }
    }
    func shutdown() {
        guard !isPreparingShutdown, !hasStopped else { return }
        isPreparingShutdown = true
        engine.prepareToQuit { [weak self] allowed in
            guard let self else { return }
            if allowed {
                authentication?.1.invalidate(); authentication = nil
                transport?.shutdown()
            } else {
                isPreparingShutdown = false
                onShutdownBlocked?()
            }
        }
    }
    func lockForInactiveScene() { transport?.post(type: "core.lock_all", payload: [:]) }
    func retrySave() {
        saveNeedsRetry = false; error = nil
        transport?.post(type: "core.retry_save", payload: [:])
    }
    func workspace(for id: String) -> CoreSnapshot? { workspaces.values.first { $0.windows.contains { $0.id == id } } }
    func spaces(_ id: String) -> [CoreSpace] { workspace(for: id)?.spaces ?? [] }
    func window(_ id: String) -> CoreWindow? { workspace(for: id)?.windows.first { $0.id == id } }
    func space(_ id: String) -> CoreSpace? {
        guard let window = window(id) else { return nil }
        return spaces(id).first { $0.id == window.spaceId }
    }
    func tab(_ id: String) -> CoreTab? {
        guard let selected = window(id)?.tabId else { return nil }
        return space(id)?.tabs.first { $0.id == selected }
    }
    func visibleTabs(_ id: String) -> [CoreTab] {
        guard let tab = tab(id) else { return [] }
        guard let group = tab.splitGroupId else { return [tab] }
        return space(id)?.tabs.filter { $0.splitGroupId == group } ?? [tab]
    }
    func transferDestinations(from windowID: String) -> [(id: String, name: String)] {
        guard engineCapabilities.contains("workspace-transfer"), let source = workspace(for: windowID),
            let space = space(windowID), space.isLocked != true else { return [] }
        return workspaces.values.sorted { $0.workspaceId < $1.workspaceId }.flatMap { workspace in
            guard workspace.workspaceId != source.workspaceId,
                workspace.spaces.contains(where: { $0.id == space.id && $0.profileId == space.profileId && $0.isLocked != true && $0.isDeleting != true })
            else { return [(id: String, name: String)]() }
            let mode = workspace.workspaceMode == "borrowed" ? "Temporary" : workspace.workspaceMode == "private" ? "Private" : "Regular"
            return workspace.windows.enumerated().map { index, window in
                (id: window.id, name: "\(space.name) · \(mode) window \(index + 1)")
            }
        }
    }
    func transferTab(_ tabID: String, from sourceWindow: String, to destinationWindow: String) {
        guard let source = workspace(for: sourceWindow), let destination = workspace(for: destinationWindow),
            let space = space(sourceWindow), !isPreparingShutdown else { return }
        transport?.post(type: "core.transfer_tab", payload: [
            "sourceWorkspaceId": source.workspaceId, "destinationWorkspaceId": destination.workspaceId,
            "windowId": destinationWindow, "spaceId": space.id, "tabId": tabID,
        ])
    }
    func focusSurface(windowID: String, index: Int) {
        guard let tabs = surfaceTabs[windowID], tabs.indices.contains(index), window(windowID)?.tabId != tabs[index] else { return }
        command("core.select_tab", windowID: windowID, extra: ["tabId": tabs[index]])
    }
    func command(_ type: String, windowID: String, extra: [String: Any] = [:]) {
        guard !isPreparingShutdown else { return }
        guard let window = window(windowID) else { return }
        var p: [String: Any] = ["windowId": windowID, "spaceId": window.spaceId]
        if let workspace = workspace(for: windowID) { p["workspaceId"] = workspace.workspaceId }
        if ["core.place_tab", "core.create_folder", "core.rename_folder", "core.collapse_folder", "core.delete_folder",
            "core.file_tabs", "core.move_folder", "core.rename_space"].contains(type) { p.removeValue(forKey: "windowId") }
        if ["core.close_tab", "core.navigate", "core.back", "core.forward", "core.reload", "core.stop"].contains(type) {
            guard let tab = extra["tabId"] as? String ?? window.tabId else { return }
            p["tabId"] = tab
        }
        for (key, value) in extra { p[key] = value }
        transport?.post(type: type, payload: p)
    }
    func maintainSession() { transport?.post(type: "core.maintain_session", payload: [:]) }
    func setRetention(windowID: String, key: String, value: String) {
        guard let retention = space(windowID)?.retention else { return }
        var values: [String: Any] = ["currentTabs": retention.currentTabs, "history": retention.history,
            "archive": retention.archive, "downloads": retention.downloads]
        values[key] = value
        command("core.set_retention", windowID: windowID, extra: values)
    }
    func createSpace(name: String, windowID: String) {
        guard let workspace = workspace(for: windowID) else { return }
        transport?.post(type: "core.create_space", payload: ["name": name, "workspaceId": workspace.workspaceId])
    }
    private func receive(_ data: Data) {
        do {
            let message = try CoreMessage(data: data)
            guard message.sessionId == transport?.sessionID, message.sequence == lastSequence + 1 else {
                throw CoreTransportError.invalidOutput
            }
            lastSequence = message.sequence
            switch (message.recipient, message.kind) {
            case ("engine", "effect"): engine.handle(message)
            case ("platform", "effect"):
                if message.type == "platform.authenticate_space" { authenticate(message) }
                else if message.type == "platform.cancel_authentication" {
                    if message.payload["requestId"] as? String == authentication?.0 {
                        authentication?.1.invalidate(); authentication = nil
                    }
                } else { assignSurface(message) }
            case ("services", "effect"):
                if message.type == "services.delete_space_data" {
                    // This isolated composition has no credential vault, sync journal,
                    // or external download ledger. Its only records are the core checkpoint.
                    let identity = message.payload.filter { ["workspaceId", "spaceId", "profileId"].contains($0.key) }
                    transport?.post(type: "services.space_data_deleted", payload: identity, sender: "services", cause: message)
                    break
                }
                guard let storage else {
                    throw CoreTransportError.invalidOutput
                }
                storage.save(message) { [weak self] saved, succeeded in
                    guard let revision = saved.payload["revision"] as? String else { return }
                    self?.transport?.post(
                        type: succeeded ? "services.session_saved" : "services.save_failed",
                        payload: ["revision": revision], sender: "services", cause: saved)
                }
            case ("ui", "projection"):
                if message.type == "ui.snapshot_begin" {
                    guard snapshotTransfer == nil,
                        let text = message.payload["revision"] as? String, UInt64(text) == projectionRevision + 1
                    else { throw CoreTransportError.invalidOutput }
                    snapshotTransfer = try CoreChunkTransfer(begin: message, identityKey: "snapshotId")
                    return
                }
                if message.type == "ui.snapshot_chunk" {
                    guard let snapshotTransfer else { throw CoreTransportError.invalidOutput }
                    try snapshotTransfer.append(message)
                    return
                }
                guard let revisionText = message.payload["revision"] as? String,
                    let revision = UInt64(revisionText), revision == projectionRevision + 1 else {
                    throw CoreTransportError.invalidOutput
                }
                if message.type == "ui.snapshot" || message.type == "ui.snapshot_commit" {
                    let bytes: Data
                    if message.type == "ui.snapshot_commit" {
                        guard let snapshotTransfer else { throw CoreTransportError.invalidOutput }
                        bytes = try snapshotTransfer.finish(message)
                        self.snapshotTransfer = nil
                    } else {
                        guard snapshotTransfer == nil else { throw CoreTransportError.invalidOutput }
                        bytes = try JSONSerialization.data(withJSONObject: message.payload)
                    }
                    let next = try JSONDecoder().decode(CoreSnapshot.self, from: bytes)
                    guard next.revision == revisionText else { throw CoreTransportError.invalidOutput }
                    applySnapshot(next)
                } else if message.type == "ui.tab_changed" {
                    guard snapshotTransfer == nil, let workspaceID = message.payload["workspaceId"] as? String,
                        let spaceID = message.payload["spaceId"] as? String,
                        let value = message.payload["tab"] as? [String: Any] else { throw CoreTransportError.invalidOutput }
                    let updated = try JSONDecoder().decode(CoreTab.self, from: JSONSerialization.data(withJSONObject: value))
                    guard let tab = workspaces[workspaceID]?.spaces.first(where: { $0.id == spaceID })?.tabs.first(where: { $0.id == updated.id })
                    else { throw CoreTransportError.invalidOutput }
                    tab.apply(updated)
                    if message.payload["recordsChanged"] as? Bool == true { recordsRevision &+= 1 }
                } else if message.type == "ui.workspace_removed", let id = message.payload["workspaceId"] as? String {
                    let windows = workspaces.removeValue(forKey: id)?.windows.map(\.id) ?? []
                    removedWindowIDs.formUnion(windows)
                    for window in windows {
                        openedWindowIDs.remove(window); claimedWindowIDs.remove(window)
                        sceneWindowIDs = sceneWindowIDs.filter { $0.value != window }
                        surfaces.removeValue(forKey: window)?.forEach { $0.removeFromSuperview() }
                        surfaceTabs.removeValue(forKey: window); leases.removeValue(forKey: window)
                        pendingAttachments.removeValue(forKey: window)
                        surfaceOwners = surfaceOwners.filter { $0.value != window }
                    }
                    pruneNativePanes()
                    onCloseWindows?(windows)
                } else { throw CoreTransportError.invalidOutput }
                projectionRevision = revision
            case ("ui", "result"):
                if message.type == "ui.records_begin" {
                    guard recordsTransfer == nil else { throw CoreTransportError.invalidOutput }
                    recordsTransfer = try CoreChunkTransfer(begin: message, identityKey: "recordsId", byteLimit: 1_048_576)
                    return
                }
                if message.type == "ui.records_chunk" {
                    guard let recordsTransfer else { throw CoreTransportError.invalidOutput }
                    try recordsTransfer.append(message); return
                }
                if message.type == "ui.records" || message.type == "ui.records_commit" {
                    let bytes: Data
                    if message.type == "ui.records_commit" {
                        guard let recordsTransfer else { throw CoreTransportError.invalidOutput }
                        bytes = try recordsTransfer.finish(message); self.recordsTransfer = nil
                    } else {
                        guard recordsTransfer == nil else { throw CoreTransportError.invalidOutput }
                        bytes = try JSONSerialization.data(withJSONObject: message.payload)
                    }
                    let page = try JSONDecoder().decode(CoreRecordsPage.self, from: bytes)
                    if let tabID = recordRequests.first(where: { $0.value == page.queryId })?.key,
                        let workspace = workspaces[page.workspaceId], workspace.workspaceClosing != true,
                        let space = workspace.spaces.first(where: { $0.id == page.spaceId }),
                        space.isLocked != true, space.isDeleting != true, space.tabs.contains(where: { $0.id == tabID }) {
                        recordsByTabID[tabID] = page
                    }
                }
                if message.type == "core.shutdown_blocked" {
                    transport?.resumeAfterBlockedShutdown()
                    engine.cancelQuitPreparation()
                    isPreparingShutdown = false
                    saveNeedsRetry = true
                    error = "Changes could not be saved. Retry saving before closing the browser."
                    onShutdownBlocked?()
                }
                if message.type == "core.operation_failed" {
                    let code = message.payload["code"] as? String ?? "unknown"
                    switch code {
                    case "authentication_canceled", "canceled": break
                    case "authentication_denied": error = "Authentication did not succeed. The Space remains locked."
                    case "authentication_unavailable": error = "Device authentication is unavailable. The Space remains locked."
                    case "persistence_failed":
                        saveNeedsRetry = true
                        error = "Changes could not be saved. Retry saving before closing the browser."
                    default: error = "The operation could not be completed (\(code))."
                    }
                }
            default: throw CoreTransportError.invalidOutput
            }
        } catch { self.error = "The control plane returned an invalid message." }
    }
    private func applySnapshot(_ next: CoreSnapshot) {
        var previous: [String: CoreTab] = [:]
        for space in workspaces[next.workspaceId]?.spaces ?? [] { for tab in space.tabs { previous[tab.id] = tab } }
        let spaces = next.spaces.map { space in
            CoreSpace(id: space.id, profileId: space.profileId, name: space.name,
                tabs: space.tabs.map { incoming in
                    guard let retained = previous[incoming.id] else { return incoming }
                    retained.apply(incoming); return retained
                }, folders: space.folders, retention: space.retention, requiresAuthentication: space.requiresAuthentication, isLocked: space.isLocked,
                isDeleting: space.isDeleting, deletionFailure: space.deletionFailure,
                contentBlockingPolicy: space.contentBlockingPolicy, contentBlockingPending: space.contentBlockingPending,
                contentBlockingFailure: space.contentBlockingFailure, searchProviderId: space.searchProviderId,
                searchSuggestionsEnabled: space.searchSuggestionsEnabled, searchProviders: space.searchProviders)
        }
        let updated = CoreSnapshot(revision: next.revision, workspaceId: next.workspaceId, spaces: spaces, windows: next.windows,
            workspaceMode: next.workspaceMode, workspaceClosing: next.workspaceClosing)
        workspaces[next.workspaceId] = updated
        if next.workspaceMode == nil || next.workspaceMode == "persistent" { snapshot = updated }
        pruneNativePanes()
        recordsRevision &+= 1
    }
    private func pruneNativePanes() {
        let remainingTabs = Set(workspaces.values.flatMap(\.spaces).flatMap(\.tabs).map(\.id))
        nativePanes = nativePanes.filter { remainingTabs.contains($0.key) }
        recordsByTabID = recordsByTabID.filter { remainingTabs.contains($0.key) }
        recordRequests = recordRequests.filter { remainingTabs.contains($0.key) }
    }
    private func authenticate(_ message: CoreMessage) {
        guard let name = message.payload["name"] as? String,
            let space = message.payload["spaceId"] as? String, let profile = message.payload["profileId"] as? String,
            let generation = message.payload["generation"] as? String else {
            error = "Invalid authentication request."; return
        }
        authentication?.1.invalidate()
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        authentication = (message.id, context)
        Task { @MainActor [weak self] in
            var outcome = "unavailable"
            var policyError: NSError?
            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) {
                do {
                    outcome = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                        localizedReason: String(localized: "Authenticate to unlock the \(name) Space in Crest.")) ? "succeeded" : "denied"
                } catch let failure as LAError {
                    switch failure.code {
                    case .userCancel, .appCancel, .systemCancel: outcome = "canceled"
                    case .passcodeNotSet, .biometryNotAvailable, .biometryNotEnrolled: outcome = "unavailable"
                    default: outcome = "denied"
                    }
                } catch { outcome = "denied" }
            }
            guard let self, self.authentication?.0 == message.id else { return }
            self.authentication = nil
            self.transport?.post(type: "platform.authentication_completed", payload: [
                "spaceId": space, "profileId": profile, "generation": generation, "outcome": outcome,
            ], sender: "platform", cause: message)
        }
    }
    private func assignSurface(_ message: CoreMessage) {
        guard message.type == "platform.assign_surface", let window = message.payload["windowId"] as? String,
            let lease = message.payload["leaseId"] as? String
        else {
            error = "Invalid surface assignment."
            return
        }
        var response: [String: Any] = ["windowId": window, "leaseId": lease]
        let outgoingViews = surfaces[window] ?? []
        let outgoingPages = surfaceOwners.filter { $0.value == window }.map(\.key)
        let pages: [String]
        if let members = message.payload["pages"] as? [[String: Any]] {
            pages = members.compactMap { $0["pageId"] as? String }
            guard pages.count == members.count, Set(pages).count == pages.count, pages.count <= 4 else {
                error = "Invalid split surface assignment."; return
            }
        } else { pages = (message.payload["pageId"] as? String).map { [$0] } ?? [] }
        var views: [CoreNativePageView] = []
        for page in pages {
            guard surfaceOwners[page] == nil || surfaceOwners[page] == window,
                engine.preparePresentation(pageID: page, windowID: window),
                let view = engine.nativeView(pageID: page)
            else {
                response["code"] = "page_already_presented"
                transport?.post(type: "platform.failed", payload: response, sender: "platform", cause: message)
                return
            }
            views.append(view)
        }
        let panes = message.payload["panes"] as? [[String: Any]]
            ?? message.payload["pages"] as? [[String: Any]] ?? []
        guard panes.count <= 4,
            Set(panes.compactMap { $0["tabId"] as? String }).count == panes.count,
            panes.allSatisfy({ $0["spaceId"] is String && $0["tabId"] is String })
        else { error = "Invalid native pane assignment."; return }
        let webViews = Dictionary(uniqueKeysWithValues: zip(pages, views))
        views = panes.compactMap { pane in
            if let pageID = pane["pageId"] as? String { return webViews[pageID] }
            guard let tabID = pane["tabId"] as? String, let spaceID = pane["spaceId"] as? String else { return nil }
            return nativePane(tabID: tabID, spaceID: spaceID, windowID: window, kind: pane["kind"] as? String ?? "web")
        }
        guard views.count == panes.count else { error = "Missing native pane."; return }
        surfaceOwners = surfaceOwners.filter { $0.value != window }
        for page in pages { surfaceOwners[page] = window }
        surfaces[window] = views
        surfaceTabs[window] = panes.compactMap { $0["tabId"] as? String }
        leases[window] = lease
        pendingAttachments[window] = message
        for view in outgoingViews where !views.contains(where: { $0 === view }) { view.removeFromSuperview() }
        for page in outgoingPages where !pages.contains(page) { engine.didDetach(pageID: page) }
        // Detached scenes may have no SwiftUI representable to perform work.
        // Native removal still completes on the main thread before the core is told.
        if views.isEmpty {
            outgoingViews.forEach { $0.removeFromSuperview() }
            attached(windowID: window, leaseID: lease)
        }
        // Nonempty assignments are acknowledged by the mounted native container.
        attachmentRevision += 1
    }
    private func nativePane(tabID: String, spaceID: String, windowID: String, kind: String) -> CoreNativePageView {
        if let (state, view) = nativePanes[tabID] {
            state.windowID = windowID; state.kind = kind
            return view
        }
        let state = CoreNativePaneState(tabID: tabID, spaceID: spaceID, windowID: windowID, kind: kind)
        let content = CoreNativeTabContent(model: self, pane: state)
        #if os(macOS)
            let view = NSHostingView(rootView: content)
        #else
            let view = CoreNativeHostedPane(content: content)
        #endif
        nativePanes[tabID] = (state, view)
        return view
    }
    @ObservationIgnored private var pendingAttachments: [String: CoreMessage] = [:]
    private(set) var attachmentRevision = 0
    func surfaceLease(_ windowID: String) -> String? { leases[windowID] }
    func attached(windowID: String, leaseID: String?) {
        guard let lease = leaseID, let message = pendingAttachments[windowID],
            leases[windowID] == lease, message.payload["leaseId"] as? String == lease
        else {
            return
        }
        pendingAttachments.removeValue(forKey: windowID)
        let selectedPage = message.payload["pageId"] as? String
        let pages = (message.payload["pages"] as? [[String: Any]] ?? []).compactMap { $0["pageId"] as? String }
        for pageID in pages where pageID != selectedPage { engine.didAttach(pageID: pageID, windowID: windowID) }
        if let selectedPage, surfaceOwners[selectedPage] == windowID { engine.didAttach(pageID: selectedPage, windowID: windowID) }
        transport?.post(
            type: "platform.surface_attached", payload: ["windowId": windowID, "leaseId": lease],
            sender: "platform", cause: message)
    }
}

@Observable @MainActor
final class CoreNativePaneState {
    let tabID: String
    let spaceID: String
    var windowID: String
    var kind: String
    init(tabID: String, spaceID: String, windowID: String, kind: String) {
        self.tabID = tabID; self.spaceID = spaceID; self.windowID = windowID; self.kind = kind
    }
}
