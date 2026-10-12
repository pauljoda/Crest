import AppKit
import os

/// Lets agents the person runs, such as coding agents, use Crest while the
/// person allows it in Settings. An agent runs the `crest-browser` helper
/// this Crest ships, which speaks the Model Context Protocol with the agent
/// and reaches Crest through a Unix domain socket that exists only while
/// agents are on, and that only this Crest's own helper may use.
///
/// The first time an agent calls a tool, the person is asked whether it may
/// use Crest, and the core keeps the answer, keyed by the agent's code
/// signature. From then on the agent reaches only the Spaces of the person's
/// own session that they allowed, as the core's `AgentReach` answers; every
/// tab it touches shows its badge, and the person can stop it in any tab.
/// Turning agents off, or forgetting an agent, ends its connections.
@MainActor
final class BrowserMacAgents {
    // MARK: - Static Variables

    static let maximumConnections = 32

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "Agents")

    // MARK: - Types

    /// One helper's connection: the agent behind it, as macOS vouches for it
    /// and as it names itself, and the core session it holds once the person
    /// allowed it.
    final class Link {
        let connection: BrowserAgentConnection
        var client: AgentClientInfo?
        var isAttached = false
        /// The agent's connection in the core, once the person allowed it.
        var sessionID: UUID?
        /// The session being begun while the person is asked, which calls
        /// that arrive meanwhile share.
        var beginning: Task<Result<UUID, BrowserAgentFailure>, Never>?
        /// The engine page of each tab that renders for the agent, and of each
        /// that keeps its activity, by tab. A later call asks again only when
        /// the tab's page changed, as when it moved to another engine.
        var heldPages: [UUID: UUID] = [:]
        var observedPages: [UUID: UUID] = [:]
        /// When the agent last gave each tab input, which may start a load a
        /// moment later.
        var lastInput: [UUID: ContinuousClock.Instant] = [:]

        init(connection: BrowserAgentConnection) {
            self.connection = connection
        }

        /// The agent program, as it vouches for the agent it runs.
        var agent: BrowserAgentPeer.Program? { connection.peer.agent?.running(client) }
    }

    // MARK: - Variables

    unowned let application: BrowserMacApplication
    unowned let windows: BrowserMacWindows
    /// Where agents' helpers connect, or nil when this launch offers none.
    let path: String?
    /// What a helper must be to be heard: this Crest's own.
    private let helper: BrowserAgentHelperRequirement?
    var listener: BrowserAgentListener?
    var links: [ObjectIdentifier: Link] = [:]
    let approvals = BrowserAgentApprovals()
    /// The work running on each tab, which the next call on that tab waits
    /// for, so calls on one tab never interleave.
    private var tabWork: [UUID: Task<Void, Never>] = [:]
    private var stopped = false

    var core: CrestCore { application.browser.core }

    // MARK: - Initializers

    init(application: BrowserMacApplication, windows: BrowserMacWindows) {
        self.application = application
        self.windows = windows
        helper = BrowserAgentHelperRequirement(bundle: .main)
        path = helper == nil ? nil : Bundle.main.bundleIdentifier.flatMap(AgentSocketLocation.path(forApp:))
    }

    // MARK: - Actions - Lifecycle

    /// Follows the person's agent preferences from now on: the socket exists
    /// while agents are on.
    func start() {
        follow()
    }

    /// Removes the socket and ends every connection for good, as the app
    /// quits.
    func stop() {
        stopped = true
        closeEndpoint()
    }

    private func follow() {
        guard !stopped else { return }
        withObservationTracking {
            apply(core.state.agentPreferences, connected: core.state.agentSessions)
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
    }

    /// Opens or removes the socket as agents are turned on or off, ends the
    /// connections of an agent the core no longer keeps connected, as when
    /// the person forgot it, and lets go of the pages of tabs an agent may no
    /// longer use, as one the person stopped it in.
    private func apply(_ preferences: AgentPreferences, connected: [AgentSessionState]) {
        guard preferences.isOn else {
            closeEndpoint()
            return
        }
        openEndpoint()
        let sessions = Dictionary(connected.map { ($0.sessionID, $0) }, uniquingKeysWith: { first, _ in first })
        for link in links.values {
            guard let sessionID = link.sessionID else { continue }
            guard let session = sessions[sessionID] else {
                end(link)
                continue
            }
            let used = Set(session.tabIDs)
            for tabID in Set(link.heldPages.keys).union(link.observedPages.keys) where !used.contains(tabID) {
                letGo(tabID, of: link)
            }
        }
    }

    private func openEndpoint() {
        guard listener == nil else { return }
        let status = application.agentEndpoint
        guard let path, let helper else {
            status.state = .failed(.unavailable)
            return
        }
        let listener = BrowserAgentListener(path: path, helper: helper) { [weak self] connection in
            // The main queue keeps connections and their lines in the order
            // they arrived.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.admit(connection) } }
        }
        do {
            try listener.start()
            self.listener = listener
            status.state = .listening
        } catch {
            Self.logger.error("The agent socket could not open: \(String(describing: error), privacy: .public)")
            status.state = .failed(error)
        }
    }

    private func closeEndpoint() {
        if let listener, !listener.stop() {
            Self.logger.error("The agent socket did not close in time.")
        }
        listener = nil
        application.agentEndpoint.state = .closed
        for link in links.values { end(link) }
        approvals.dismissAll()
    }

    // MARK: - Actions - Tabs

    /// Runs `work` on tab `tabID` once the work an agent started on it before
    /// has finished, so calls on one tab never interleave.
    func serially(
        on tabID: UUID, _ work: @escaping @MainActor () async throws(BrowserAgentFailure) -> AgentToolResult
    ) async throws(BrowserAgentFailure) -> AgentToolResult {
        let earlier = tabWork[tabID]
        let result = Task { @MainActor () async -> Result<AgentToolResult, BrowserAgentFailure> in
            await earlier?.value
            do throws(BrowserAgentFailure) {
                return .success(try await work())
            } catch {
                return .failure(error)
            }
        }
        tabWork[tabID] = Task { _ = await result.value }
        return try await result.value.get()
    }

    /// The live page of tab `tabID` when it has one, which an agent holds.
    func agentPage(_ tabID: UUID) -> BrowserPage? {
        application.pages.residentPage(ofTab: tabID)
    }
}
