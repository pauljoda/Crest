import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

#if !CREST_CHROMIUM_HOST
@main
struct ControlPlaneApp: App {
    #if os(macOS)
        @NSApplicationDelegateAdaptor(ControlPlaneAppDelegate.self) private var delegate
    #else
        @UIApplicationDelegateAdaptor(ControlPlaneMobileAppDelegate.self) private var delegate
    #endif
    @State private var model: ControlPlaneModel

    init() {
        // These values are set before constructing any existing Crest platform services.
        // This target never constructs BrowserStore.production, CloudKit, Sparkle, or a credential vault.
        setenv("CREST_ISOLATED_SESSION", "1", 1)
        setenv("CREST_ISOLATED_PERSISTENCE_ID", "control-plane-\(UUID().uuidString.lowercased())", 1)
        let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        _model = State(initialValue: ControlPlaneModel(engine: AppleWebKitAdapter(), persistsSession: !isTestHost))
    }
    var body: some Scene {
        WindowGroup("Crest Control Plane", id: "browser", for: String.self) { restorationID in
            ControlPlaneWindow(model: model, restorationID: restorationID)
                .onAppear { delegate.model = model }
        }
        #if os(macOS)
            .defaultSize(width: 1200, height: 820)
        #endif
    }
}

#if os(macOS)
    @MainActor
    final class ControlPlaneAppDelegate: NSObject, NSApplicationDelegate {
        weak var model: ControlPlaneModel?
        func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
            guard let model, !model.hasStopped else { return .terminateNow }
            model.onStopped = { sender.reply(toApplicationShouldTerminate: true) }
            model.onShutdownBlocked = { sender.reply(toApplicationShouldTerminate: false) }
            model.shutdown()
            return .terminateLater
        }
    }
#else
    @MainActor
    final class ControlPlaneMobileAppDelegate: NSObject, UIApplicationDelegate {
        private var discardedScenes: Set<String> = []
        weak var model: ControlPlaneModel? {
            didSet {
                guard let model else { return }
                for scene in discardedScenes { model.discardScene(scene) }
                discardedScenes.removeAll()
            }
        }
        func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
            for scene in sceneSessions {
                if let model { model.discardScene(scene.persistentIdentifier) }
                else { discardedScenes.insert(scene.persistentIdentifier) }
            }
        }
    }
#endif

#endif

struct ControlPlaneWindow: View {
    @Bindable var model: ControlPlaneModel
    @Binding var restorationID: String?
    var restoreAdditionalWindow: ((String) -> Void)? = nil
    var preclaimedWindowID: String? = nil
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var windowID = ""
    @State private var address = ""
    @FocusState private var addressFocused: Bool
    @State private var opened = false
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var deletingSpace: CoreSpace?
    @State private var persistentWindowID = ""
    @State private var transientWindowIDs: [String] = []

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Crest").font(.largeTitle.weight(.semibold))
                Text("Control Plane · \(model.engineDisplayName)").font(.caption).foregroundStyle(.secondary)
                Picker(
                    "Space",
                    selection: Binding(
                        get: { model.window(windowID)?.spaceId ?? "" },
                        set: {
                            model.command("core.switch_space", windowID: windowID, extra: ["spaceId": $0])
                        })
                ) {
                    ForEach(model.spaces(windowID).filter { $0.isDeleting != true }) { space in Text(space.name).tag(space.id) }
                }
                List {
                    ForEach(model.space(windowID)?.tabs ?? []) { tab in
                        HStack {
                            Button {
                                model.command("core.select_tab", windowID: windowID, extra: ["tabId": tab.id])
                                compactColumn = .detail
                            } label: {
                                Label(tab.title, systemImage: tab.kind == "settings" ? "gearshape" : "globe")
                                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            Button("Close \(tab.title)", systemImage: "xmark") {
                                model.command("core.close_tab", windowID: windowID, extra: ["tabId": tab.id])
                            }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                        }
                        .listRowBackground(
                            model.window(windowID)?.tabId == tab.id ? Color.accentColor.opacity(0.14) : Color.clear)
                        .contextMenu {
                            if tab.kind == "web", model.engineCapabilities.contains("page-residency") {
                                Button(tab.keepsPageLoaded ? "Allow automatic unloading" : "Keep page loaded") {
                                    tabCommand("core.set_tab_residency", tab, ["keepsPageLoaded": !tab.keepsPageLoaded])
                                }
                            }
                            Button("Duplicate") { tabCommand("core.duplicate_tab", tab) }
                            Button(tab.placement == "pinned" ? "Unpin" : "Pin") {
                                tabCommand("core.place_tab", tab, ["placement": tab.placement == "pinned" ? "saved" : "pinned"])
                            }
                            Button(tab.placement == "current" ? "Save tab" : "Move to current tabs") {
                                tabCommand("core.place_tab", tab, ["placement": tab.placement == "current" ? "saved" : "current"])
                            }
                            ForEach(splitCandidates(for: tab)) { target in
                                Button("Split with \(target.title)") { tabCommand("core.join_split", tab, ["targetTabId": target.id]) }
                            }
                            if tab.splitGroupId != nil {
                                Button("Remove from split") { tabCommand("core.leave_split", tab) }
                            }
                            let destinations = model.transferDestinations(from: windowID)
                            ForEach(destinations, id: \.id) { destination in
                                Button("Move to \(destination.name)") {
                                    model.transferTab(tab.id, from: windowID, to: destination.id)
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                if model.engineCapabilities.contains("page-residency") {
                    Button("Unload inactive pages", systemImage: "memorychip") { model.releaseInactivePages() }
                }
                Button("New tab", systemImage: "plus") {
                    model.command("core.new_tab", windowID: windowID)
                    compactColumn = .detail
                }.keyboardShortcut("t")
                Button("New Space", systemImage: "square.grid.2x2") {
                    model.createSpace(name: "Space \(model.spaces(windowID).count + 1)", windowID: windowID)
                }
                .disabled(model.workspace(for: windowID)?.workspaceMode == "borrowed")
                if model.workspace(for: windowID)?.workspaceMode != "borrowed" {
                    Button("Delete Space", systemImage: "trash", role: .destructive) { deletingSpace = model.space(windowID) }
                        .disabled(!model.engineCapabilities.contains("profile-deletion")
                            || model.spaces(windowID).filter { $0.isDeleting != true }.count < 2 || model.space(windowID)?.isLocked == true)
                    ForEach(model.spaces(windowID).filter { $0.isDeleting == true }) { pending in
                        if pending.deletionFailure != nil {
                            Button("Retry deleting \(pending.name)") {
                                model.command("core.retry_space_deletion", windowID: windowID, extra: ["spaceId": pending.id])
                            }
                        } else { Text("Deleting \(pending.name)…").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                #if os(macOS)
                    Menu("New window") {
                        Button("Private window") { openWorkspace("private") }
                        Button("Temporary window in this Space") { openWorkspace("borrowed") }
                    }
                    .disabled(model.space(windowID)?.isLocked == true || !model.engineCapabilities.contains("workspace-profiles"))
                #else
                    Menu("Browsing mode") {
                        Button("Private session") { openWorkspace("private") }
                            .disabled(model.space(windowID)?.isLocked == true || !model.engineCapabilities.contains("workspace-profiles"))
                        Button("Temporary session in this Space") { openWorkspace("borrowed") }
                            .disabled(model.space(windowID)?.isLocked == true || !model.engineCapabilities.contains("workspace-profiles"))
                        if windowID != persistentWindowID {
                            Button("Return to regular browsing") { showMobileWindow(persistentWindowID) }
                            Button("Close this session", role: .destructive) {
                                let closing = windowID
                                showMobileWindow(persistentWindowID)
                                model.closeWindow(closing)
                                transientWindowIDs.removeAll { $0 == closing }
                            }
                        }
                        ForEach(transientWindowIDs.filter { $0 != windowID && !model.removedWindowIDs.contains($0) }, id: \.self) { id in
                            Button(model.workspace(for: id)?.workspaceMode == "private" ? "Return to private session" : "Return to temporary session") {
                                showMobileWindow(id)
                            }
                        }
                    }
                #endif
                HStack {
                    Button("History", systemImage: "clock") {
                        model.command("core.open_records", windowID: windowID, extra: ["kind": "history"])
                        compactColumn = .detail
                    }
                    Button("Archive", systemImage: "archivebox") {
                        model.command("core.open_records", windowID: windowID, extra: ["kind": "archive"])
                        compactColumn = .detail
                    }
                }
                Button("Settings", systemImage: "gearshape") {
                    model.command("core.open_settings", windowID: windowID, extra: ["disposition": "foreground"])
                    compactColumn = .detail
                }
                if model.space(windowID)?.requiresAuthentication == true && model.space(windowID)?.isLocked != true {
                    Button("Lock Space", systemImage: "lock") { model.command("core.lock_space", windowID: windowID) }
                }
                Text(workspaceDescription)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding().navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .confirmationDialog("Delete \(deletingSpace?.name ?? "Space")?", isPresented: Binding(
                get: { deletingSpace != nil }, set: { if !$0 { deletingSpace = nil } })
            ) {
                Button("Delete Space", role: .destructive) {
                    if let space = deletingSpace { model.command("core.delete_space", windowID: windowID, extra: ["spaceId": space.id]) }
                    deletingSpace = nil
                }
            } message: { Text("This removes the Space’s tabs, history and website data, and closes its temporary windows.") }
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Button("Back", systemImage: "chevron.left") { model.command("core.back", windowID: windowID) }
                        .disabled(model.tab(windowID)?.canGoBack != true)
                    Button("Forward", systemImage: "chevron.right") {
                        model.command("core.forward", windowID: windowID)
                    }
                    .disabled(model.tab(windowID)?.canGoForward != true)
                    Button("Reload", systemImage: "arrow.clockwise") {
                        model.command("core.reload", windowID: windowID)
                    }
                    .disabled(model.tab(windowID)?.kind != "web")
                    TextField("Address", text: $address).textFieldStyle(.roundedBorder)
                        .focused($addressFocused).autocorrectionDisabled().onSubmit(navigate)
                        #if !os(macOS)
                            .textInputAutocapitalization(.never).keyboardType(.webSearch).submitLabel(.go)
                        #endif
                    Button("Go", action: navigate).keyboardShortcut(.return, modifiers: [])
                }
                .labelStyle(.iconOnly).padding(12)
                if model.visibleTabs(windowID).count > 1 {
                    HStack(spacing: 0) {
                        ForEach(model.visibleTabs(windowID)) { tab in
                            Button {
                                tabCommand("core.select_tab", tab)
                            } label: {
                                Text(tab.title).lineLimit(1).frame(maxWidth: .infinity).padding(8)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .background(model.window(windowID)?.tabId == tab.id ? Color.accentColor.opacity(0.14) : .clear)
                            .accessibilityLabel("Focus \(tab.title)")
                        }
                    }
                }
                if let error = model.error {
                    HStack {
                        Text(error).font(.callout)
                        Spacer()
                        if model.saveNeedsRetry { Button("Retry save") { model.retrySave() } }
                        Button("Dismiss") { model.error = nil }
                    }
                    .padding(10).background(.orange.opacity(0.15))
                }
                ZStack {
                    CoreNativeSurface(model: model, windowID: windowID, revision: model.attachmentRevision)
                    if model.space(windowID)?.isLocked == true {
                        ContentUnavailableView {
                            Label("Space locked", systemImage: "lock")
                        } description: {
                            Text("Authenticate on this device to open this Space.")
                        } actions: {
                            Button("Unlock Space") { model.command("core.unlock_space", windowID: windowID) }
                        }
                    } else if model.window(windowID)?.tabId == nil {
                        ContentUnavailableView(
                            "Start browsing", systemImage: "globe",
                            description: Text("Enter an address or open a new tab."))
                    }
                }
            }
        }
        .onAppear {
            #if os(macOS)
                openBrowserWindow()
            #endif
        }
        #if os(macOS)
            .background(CoreWindowLifetime { model.closeWindow(windowID) })
        #else
            .background(CoreWindowLifetime { openBrowserWindow(sceneID: $0) })
        #endif
        .onChange(of: model.tab(windowID)?.url) { _, url in if !addressFocused { address = url ?? "" } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.lockForInactiveScene() } }
        .onChange(of: model.window(windowID)?.tabId) { _, _ in
            address = model.tab(windowID)?.url ?? ""
            addressFocused = model.tab(windowID)?.kind == "startpage"
        }
        .onChange(of: model.removedWindowIDs) { _, ids in
            #if os(macOS)
                if ids.contains(windowID) { dismiss() }
            #else
                transientWindowIDs.removeAll { ids.contains($0) }
                if ids.contains(windowID) { showMobileWindow(persistentWindowID) }
            #endif
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                model.maintainSession()
                do { try await Task.sleep(for: .seconds(15 * 60)) } catch { return }
            }
        }
        .disabled(model.hasStopped || model.isPreparingShutdown || model.workspace(for: windowID)?.workspaceClosing == true)
    }
    private func openBrowserWindow(sceneID: String? = nil) {
        guard !opened else { return }
        opened = true
        windowID = preclaimedWindowID ?? model.claimWindowID(restorationID, sceneID: sceneID)
        persistentWindowID = windowID
        restorationID = windowID
        model.openWindow(windowID)
        if let sceneID { model.bindScene(sceneID, windowID: windowID) }
        #if os(macOS)
            for id in model.remainingWindowsToRestore() {
                if let restoreAdditionalWindow { restoreAdditionalWindow(id) }
                else { openWindow(id: "browser", value: id) }
            }
        #endif
    }
    private func navigate() {
        addressFocused = false
        model.command("core.navigate_input", windowID: windowID, extra: ["input": address])
    }
    private var workspaceDescription: String {
        switch model.workspace(for: windowID)?.workspaceMode {
        case "private": "Private window\nBrowsing records and website data stay in memory."
        case "borrowed": "Temporary window\nUses this Space’s website session. Browsing records stay in memory."
        default: "Experimental session\n\(model.sessionDescription)"
        }
    }
    private func openWorkspace(_ mode: String) {
        #if os(macOS)
        guard let id = model.prepareWorkspaceWindow(from: windowID, mode: mode) else { return }
        if let restoreAdditionalWindow { restoreAdditionalWindow(id) }
        else { openWindow(id: "browser", value: id) }
        #else
        guard let id = model.openWorkspaceInScene(from: windowID, ownerWindowID: persistentWindowID, mode: mode) else { return }
        transientWindowIDs.append(id)
        showMobileWindow(id)
        #endif
    }
    private func showMobileWindow(_ id: String) {
        windowID = id
        address = model.tab(id)?.url ?? ""
        addressFocused = false
    }
    private func tabCommand(_ type: String, _ tab: CoreTab, _ extra: [String: Any] = [:]) {
        var payload = extra; payload["tabId"] = tab.id
        model.command(type, windowID: windowID, extra: payload)
    }
    private func splitCandidates(for tab: CoreTab) -> [CoreTab] {
        (model.space(windowID)?.tabs ?? []).filter {
            tab.kind != "startpage" && $0.kind != "startpage" && $0.id != tab.id
                && ($0.splitGroupId == nil || $0.splitGroupId != tab.splitGroupId)
        }
    }
}

struct CoreNativeTabContent: View {
    @Bindable var model: ControlPlaneModel
    @Bindable var pane: CoreNativePaneState
    var body: some View {
        Group {
            if pane.kind == "settings" {
                CoreSpaceSettings(model: model, windowID: pane.windowID)
            } else if pane.kind == "history" || pane.kind == "archive" {
                CoreRecordsView(model: model, pane: pane)
            } else if pane.kind == "startpage" {
                ContentUnavailableView("Start browsing", systemImage: "globe",
                    description: Text("Enter an address or search above."))
            } else if pane.kind == "web" {
                if let failure = model.spaces(pane.windowID).first(where: { $0.id == pane.spaceID })?
                    .tabs.first(where: { $0.id == pane.tabID })?.failure {
                    ContentUnavailableView("Page unavailable", systemImage: "exclamationmark.triangle",
                        description: Text(failure))
                } else { ProgressView("Opening page") }
            } else {
                ContentUnavailableView("Native tab", systemImage: "rectangle.on.rectangle")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CoreSpaceSettings: View {
    @Bindable var model: ControlPlaneModel
    let windowID: String
    var body: some View {
        Form {
            if let space = model.space(windowID) {
                Section("\(space.name) browsing") {
                    Picker("Search engine", selection: Binding(
                        get: { space.searchProviderId ?? "google" },
                        set: { model.command("core.select_search_provider", windowID: windowID,
                            extra: ["providerId": $0, "suggestionsEnabled": space.searchSuggestionsEnabled ?? false]) }
                    )) {
                        ForEach(space.searchProviders ?? []) { provider in Text(provider.name).tag(provider.id) }
                    }
                    if model.engineCapabilities.contains("content-blocking") {
                        Picker("Content blocking", selection: Binding(
                            get: { space.contentBlockingPolicy ?? "balanced" },
                            set: { model.command("core.set_content_blocking", windowID: windowID, extra: ["policy": $0]) }
                        )) {
                            Text("Balanced").tag("balanced"); Text("Off").tag("off")
                        }
                        Text("Changes apply on the next navigation or reload.")
                            .font(.callout).foregroundStyle(.secondary)
                        if space.contentBlockingPending == true { ProgressView("Applying protection…") }
                        if space.contentBlockingFailure != nil {
                            Button("Retry content blocking") { model.command("core.retry_content_blocking", windowID: windowID) }
                        }
                    }
                    if let retention = space.retention {
                        Picker("Archive inactive tabs", selection: retentionBinding("currentTabs", retention.currentTabs)) {
                            Text("After 12 hours").tag("after12Hours")
                            Text("After 24 hours").tag("after24Hours")
                            Text("After 7 days").tag("after7Days")
                            Text("After 30 days").tag("after30Days")
                            Text("Never").tag("never")
                        }
                        retentionPicker("Keep history", key: "history", value: retention.history)
                        retentionPicker("Keep archived tabs", key: "archive", value: retention.archive)
                    }
                    Toggle("Require device authentication", isOn: Binding(
                        get: { space.requiresAuthentication ?? false },
                        set: { model.command("core.set_space_access", windowID: windowID, extra: ["requiresAuthentication": $0]) }
                    ))
                    Text("Addresses open directly. Other text is searched with this Space’s search engine.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
    private func retentionBinding(_ key: String, _ value: String) -> Binding<String> {
        Binding(get: { value }, set: { model.setRetention(windowID: windowID, key: key, value: $0) })
    }
    private func retentionPicker(_ title: String, key: String, value: String) -> some View {
        Picker(title, selection: retentionBinding(key, value)) {
            Text("1 day").tag("oneDay"); Text("1 week").tag("oneWeek")
            Text("30 days").tag("thirtyDays"); Text("90 days").tag("ninetyDays")
            Text("1 year").tag("oneYear"); Text("Forever").tag("forever")
        }
    }
}

#if os(macOS)
    private struct CoreWindowLifetime: NSViewRepresentable {
        let closed: @MainActor () -> Void
        func makeNSView(context: Context) -> CoreWindowObserver { CoreWindowObserver(closed: closed) }
        func updateNSView(_ view: CoreWindowObserver, context: Context) {}
    }

    @MainActor
    private final class CoreWindowObserver: NSView {
        private let closed: @MainActor () -> Void
        init(closed: @escaping @MainActor () -> Void) {
            self.closed = closed
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowClosed), name: NSWindow.willCloseNotification, object: window)
            }
        }
        @objc private func windowClosed() { closed() }
    }

    private struct CoreNativeSurface: NSViewRepresentable {
        let model: ControlPlaneModel
        let windowID: String
        let revision: Int
        func makeNSView(context: Context) -> CoreSurfaceContainer { CoreSurfaceContainer() }
        func updateNSView(_ container: CoreSurfaceContainer, context: Context) {
            container.resolve = { (model.surfaces[windowID] ?? [], model.surfaceLease(windowID)) }
            container.attached = { model.attached(windowID: windowID, leaseID: $0) }
            container.onPageFocused = { model.focusSurface(windowID: windowID, index: $0) }
            container.reconcile()
        }
    }

    @MainActor
    private final class CoreSurfaceContainer: NSView {
        var resolve: (() -> ([NSView], String?))?
        var attached: ((String?) -> Void)?
        var onPageFocused: ((Int) -> Void)?
        private var mouseMonitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(reconcile), name: NSWindow.didBecomeKeyNotification, object: window)
                mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    guard let self, event.window === self.window, let (views, _) = self.resolve?() else { return event }
                    let point = self.convert(event.locationInWindow, from: nil)
                    if let index = views.firstIndex(where: { $0.superview === self && $0.frame.contains(point) }) {
                        self.onPageFocused?(index)
                    }
                    return event
                }
            }
            reconcile()
        }
        override func layout() { super.layout(); reconcile() }
        @objc func reconcile() {
            guard let (views, lease) = resolve?() else { return }
            // A background scene may apply a SwiftUI update after a newer core
            // assignment. Read the current lease at attachment time, not body time.
            for child in subviews where !views.contains(where: { $0 === child }) { child.removeFromSuperview() }
            for view in views where view.superview !== self {
                if window != nil {
                    view.removeFromSuperview(); view.autoresizingMask = [.width, .height]; addSubview(view)
                }
            }
            for (index, view) in views.enumerated() where view.superview === self {
                let width = bounds.width / CGFloat(views.count)
                view.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
            }
            if views.isEmpty || window != nil && views.allSatisfy({ $0.superview === self }) { attached?(lease) }
        }
    }
#else
    @MainActor
    final class CoreNativeHostedPane: UIView {
        private let host: UIHostingController<CoreNativeTabContent>
        init(content: CoreNativeTabContent) {
            host = UIHostingController(rootView: content)
            super.init(frame: .zero)
            host.view.backgroundColor = .clear
            host.sizingOptions = []
        }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var responder: UIResponder? = superview
            while let candidate = responder, !(candidate is UIViewController) { responder = candidate.next }
            let parent = window == nil ? nil : responder as? UIViewController
            guard host.parent !== parent else { return }
            if host.parent != nil {
                host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent()
            }
            if let parent {
                parent.addChild(host); addSubview(host.view)
                host.view.frame = bounds; host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                host.didMove(toParent: parent)
            }
        }
        override func layoutSubviews() { super.layoutSubviews(); host.view.frame = bounds }
    }

    private struct CoreWindowLifetime: UIViewRepresentable {
        let connected: @MainActor (String) -> Void
        func makeUIView(context: Context) -> CoreWindowObserver { CoreWindowObserver() }
        func updateUIView(_ view: CoreWindowObserver, context: Context) {
            view.connected = connected
            view.reportScene()
        }
    }

    @MainActor
    private final class CoreWindowObserver: UIView {
        var connected: (@MainActor (String) -> Void)?
        private var reportedScene: String?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportScene()
        }
        func reportScene() {
            guard let id = window?.windowScene?.session.persistentIdentifier,
                id != reportedScene, connected != nil else { return }
            reportedScene = id
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window?.windowScene?.session.persistentIdentifier == id else { return }
                self.connected?(id)
            }
        }
    }

    private struct CoreNativeSurface: UIViewRepresentable {
        let model: ControlPlaneModel
        let windowID: String
        let revision: Int
        func makeUIView(context: Context) -> CoreSurfaceContainer { CoreSurfaceContainer() }
        func updateUIView(_ container: CoreSurfaceContainer, context: Context) {
            container.resolve = { (model.surfaces[windowID] ?? [], model.surfaceLease(windowID)) }
            container.attached = { model.attached(windowID: windowID, leaseID: $0) }
            container.onPageFocused = { model.focusSurface(windowID: windowID, index: $0) }
            container.reconcile()
        }
    }

    @MainActor
    private final class CoreSurfaceContainer: UIView, UIGestureRecognizerDelegate {
        var resolve: (() -> ([UIView], String?))?
        var attached: ((String?) -> Void)?
        var onPageFocused: ((Int) -> Void)?
        override init(frame: CGRect) {
            super.init(frame: frame)
            let gesture = UITapGestureRecognizer(target: nil, action: nil)
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false; gesture.delaysTouchesEnded = false
            gesture.delegate = self
            addGestureRecognizer(gesture)
        }
        required init?(coder: NSCoder) { nil }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if let (views, _) = resolve?() {
                let point = touch.location(in: self)
                if let index = views.firstIndex(where: { $0.superview === self && $0.frame.contains(point) }) {
                    onPageFocused?(index)
                }
            }
            // Focus observes the touch without recognizing, delaying, or
            // competing with a native switch, text field, scroll, or web gesture.
            return false
        }
        override func didMoveToWindow() { super.didMoveToWindow(); reconcile() }
        override func layoutSubviews() { super.layoutSubviews(); reconcile() }
        func reconcile() {
            guard let (views, lease) = resolve?() else { return }
            for child in subviews where !views.contains(where: { $0 === child }) { child.removeFromSuperview() }
            for view in views where view.superview !== self {
                if window != nil {
                    view.removeFromSuperview(); view.autoresizingMask = [.flexibleWidth, .flexibleHeight]; addSubview(view)
                }
            }
            for (index, view) in views.enumerated() where view.superview === self {
                let vertical = bounds.width < 600
                let length = (vertical ? bounds.height : bounds.width) / CGFloat(views.count)
                view.frame = vertical
                    ? CGRect(x: 0, y: CGFloat(index) * length, width: bounds.width, height: length)
                    : CGRect(x: CGFloat(index) * length, y: 0, width: length, height: bounds.height)
            }
            if views.isEmpty || window != nil && views.allSatisfy({ $0.superview === self }) { attached?(lease) }
        }
    }
#endif
