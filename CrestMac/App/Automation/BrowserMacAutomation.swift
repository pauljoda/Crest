import AppKit
import os

/// Lets local tools, such as scripts and coding agents, control Crest while
/// the person allows it in Settings. Tools connect to a Unix domain socket
/// only the person's own user can reach (`BrowserAutomationEndpoint`), which
/// exists only while automation is on, and speak JSON-RPC 2.0, one message
/// per line.
///
/// A tool starts with `hello`, naming itself. The first time a tool connects
/// from a program, the person is asked whether it may control Crest, and the
/// core keeps the answer. From then on the tool reaches only the Spaces of
/// the person's own session that they allowed, as the core's
/// `AutomationReach` answers, never a private window and nothing in a locked
/// Space. Turning automation off, or forgetting a tool, ends its connections.
@MainActor
final class BrowserMacAutomation {
    // MARK: - Static Variables

    /// The protocol version this Crest speaks, which `hello` checks.
    static let protocolVersion = 1
    /// How long `tabs.close` waits for a page the core asked to answer.
    static let closeWait = Duration.seconds(2)

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "Automation")

    // MARK: - Types

    /// One tool's connection: the tool it said it is once the person approved
    /// it, and the request being answered, which the next waits for, so a
    /// tool hears its answers in the order it asked.
    final class Session {
        let connection: BrowserAutomationConnection
        var tool: AutomationTool?
        var answering: Task<Void, Never>?
        /// The connection ends once the answer being written is sent.
        var endsAfterAnswer = false

        init(connection: BrowserAutomationConnection) {
            self.connection = connection
        }
    }

    /// A question waiting on the person about one tool, and what closes it
    /// when automation goes off before they answer.
    private struct Approval {
        let answer: Task<Bool, Never>
        let dismissal: BrowserPromptDismissal
    }

    // MARK: - Variables

    unowned let application: BrowserMacApplication
    unowned let windows: BrowserMacWindows
    /// Where tools connect, or nil when this launch offers no socket.
    let path: String?
    private var listener: BrowserAutomationListener?
    private var sessions: [ObjectIdentifier: Session] = [:]
    /// The questions waiting on the person, by tool, so a tool that connects
    /// again while it is asked about is asked once.
    private var approvals: [String: Approval] = [:]
    private let dialogs = BrowserDialogPresenter()
    private var stopped = false

    var core: CrestCore { application.browser.core }

    // MARK: - Initializers

    init(application: BrowserMacApplication, windows: BrowserMacWindows) {
        self.application = application
        self.windows = windows
        path = BrowserAutomationEndpoint.path(for: .current)
    }

    // MARK: - Actions - Lifecycle

    /// Follows the person's automation preferences from now on: the socket
    /// exists while automation is on.
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
            apply(core.state.automationPreferences)
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
    }

    /// Opens or removes the socket as automation is turned on or off, and
    /// ends the connections of a tool the person forgot.
    private func apply(_ preferences: AutomationPreferences) {
        guard preferences.isOn else {
            closeEndpoint()
            return
        }
        openEndpoint()
        for session in sessions.values where session.tool.map({ !preferences.tools.contains($0) }) == true {
            end(session)
        }
    }

    private func openEndpoint() {
        guard listener == nil, let path else { return }
        let listener = BrowserAutomationListener(path: path) { [weak self] connection in
            // The main queue keeps connections and their lines in the order
            // they arrived.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.admit(connection) } }
        }
        do {
            try listener.start()
            self.listener = listener
        } catch {
            Self.logger.error("The automation socket could not open: \(String(describing: error), privacy: .public)")
        }
    }

    private func closeEndpoint() {
        listener?.stop()
        listener = nil
        for session in sessions.values { end(session) }
        for approval in approvals.values { approval.dismissal.dismiss() }
    }

    // MARK: - Actions - Connections

    private func admit(_ connection: BrowserAutomationConnection) {
        guard listener != nil else {
            connection.close()
            return
        }
        let session = Session(connection: connection)
        let key = ObjectIdentifier(session)
        sessions[key] = session
        connection.open { [weak self] line in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(line, in: key) } }
        } ended: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.forget(key) } }
        }
    }

    private func forget(_ key: ObjectIdentifier) {
        sessions[key]?.answering?.cancel()
        sessions[key] = nil
    }

    private func end(_ session: Session) {
        session.answering?.cancel()
        session.connection.close()
        sessions[ObjectIdentifier(session)] = nil
    }

    /// Answers `line` once the session's earlier requests are answered.
    private func receive(_ line: Data, in key: ObjectIdentifier) {
        guard let session = sessions[key] else { return }
        let earlier = session.answering
        session.answering = Task { [weak self] in
            await earlier?.value
            guard let self, sessions[key] != nil, !Task.isCancelled else { return }
            let answer = await answer(line, in: session)
            guard sessions[key] != nil else { return }
            session.connection.send(answer)
            if session.endsAfterAnswer { end(session) }
        }
    }

    // MARK: - Actions - Requests

    private func answer(_ line: Data, in session: Session) async -> Data {
        let request: BrowserAutomationRequest
        do {
            request = try BrowserAutomationRequest(line: line)
        } catch {
            return BrowserAutomationRequest.refusal(error, id: nil)
        }
        do {
            return try await perform(request, in: session)
        } catch {
            return BrowserAutomationRequest.refusal(error, id: request.id)
        }
    }

    /// Answers a request with the method it names, once the tool is approved
    /// for any method but `hello`.
    private func perform(
        _ request: BrowserAutomationRequest, in session: Session
    ) async throws(BrowserAutomationError) -> Data {
        guard core.state.automationPreferences.isOn else { throw .automationOff }
        guard let method = BrowserAutomationMethod.named(request.method) else {
            throw .methodNotFound(request.method)
        }
        if !method.isOpen {
            guard let tool = session.tool else { throw .helloRequired }
            guard core.state.automationPreferences.tools.contains(tool) else { throw .notApproved }
        }
        return try await method.answer(request, on: self, in: session)
    }

    // MARK: - Actions - Hello

    /// Checks the tool's protocol version and learns which tool it is, asking
    /// the person the first time a tool connects from its program.
    func hello(
        _ hello: BrowserAutomationHello, in session: Session
    ) async throws(BrowserAutomationError) -> BrowserAutomationGreeting {
        guard hello.protocol == Self.protocolVersion else { throw .unsupportedProtocol(Self.protocolVersion) }
        let name = hello.client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .invalidParams("“client.name” is empty.") }
        let tool = AutomationTool(name: name, path: session.connection.peer.path)
        if !core.state.automationPreferences.tools.contains(tool) {
            guard await approve(tool) else {
                session.endsAfterAnswer = true
                throw .declined
            }
            do { try core.send(ApproveAutomationTool(tool: tool)) } catch { throw .refused(error.explanation) }
        }
        session.tool = tool
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return BrowserAutomationGreeting(
            protocol: Self.protocolVersion, crest: .init(version: version),
            methods: BrowserAutomationMethod.approvedNames)
    }

    /// Whether the person lets `tool` control Crest. A tool asked about
    /// already waits for the same answer, and turning automation off closes
    /// the question unanswered.
    private func approve(_ tool: AutomationTool) async -> Bool {
        let key = tool.name + "\u{0}" + tool.path
        if let asking = approvals[key] { return await asking.answer.value && !asking.dismissal.isDismissed }
        let dismissal = BrowserPromptDismissal()
        let answer = Task { [dialogs] in
            await dialogs.approveAutomationTool(name: tool.name, path: tool.path, dismissal: dismissal)
        }
        approvals[key] = Approval(answer: answer, dismissal: dismissal)
        let approved = await answer.value
        approvals[key] = nil
        return approved && !dismissal.isDismissed
    }
}
