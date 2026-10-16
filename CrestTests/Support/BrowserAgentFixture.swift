import AppKit
import Darwin
import XCTest

@testable import Crest

/// Runs public native tool dispatch with an isolated, approved agent session.
@MainActor
final class BrowserAgentFixture {
    // MARK: - Types

    final class DeferredDismissal: BrowserPageDismissalAuthorizing {
        // MARK: - Variables

        var pending: (@MainActor () -> Bool)?

        // MARK: - Actions - Confirmation

        func performDismissal(
            of assignments: [BrowserTabRuntimeAssignment], in browser: BrowserStore,
            operation: @escaping @MainActor () -> Bool
        ) -> Bool {
            pending = operation
            return false
        }

        func resolve(_ allowed: Bool) -> Bool {
            let operation = pending
            pending = nil
            return allowed && operation?() == true
        }
    }

    // MARK: - Variables

    let host = WebKitShellHost()
    let application: BrowserMacApplication
    let windows: BrowserMacWindows
    let agents: BrowserMacAgents
    let link: BrowserMacAgents.Link
    let sessionID = UUID()
    let space: SpaceModel
    var core: CrestCore { application.browser.core }

    // MARK: - Initializers

    init() throws {
        application = try BrowserMacApplication()
        windows = BrowserMacWindows(application: application, engineHost: host)
        agents = BrowserMacAgents(application: application, windows: windows)
        space = try XCTUnwrap(application.browser.shownSpace)
        let identity = AgentIdentity(teamID: nil, signingID: nil, path: "/private/tmp/crest-test-agent", client: nil)
        var descriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw POSIXError(.EIO) }
        Darwin.close(descriptors[1])
        let peer = BrowserAgentPeer(helperProcessID: getpid(), agent: nil)
        link = BrowserMacAgents.Link(connection: BrowserAgentConnection(descriptor: descriptors[0], peer: peer))
        try core.send(SetAgents(isOn: true))
        try core.send(AllowAgentSpace(spaceID: space.id, allowed: true))
        try core.send(ApproveAgent(agent: ApprovedAgent(identity: identity, name: "Test")))
        try core.send(BeginAgentSession(sessionID: sessionID, identity: identity, name: "Test"))
    }

    // MARK: - Actions - Tools

    func invoke(_ name: String, _ arguments: [String: AgentJSON] = [:]) async throws -> AgentJSON {
        let tool = try XCTUnwrap(BrowserAgentTool.named(name))
        let answer = try await tool.perform(
            BrowserAgentCall(agents: agents, link: link, sessionID: sessionID, arguments: .object(arguments)))
        if answer.isError { throw BrowserAgentFailure(answer.content.first?.text ?? "The tool failed.") }
        let text = try XCTUnwrap(answer.content.first?.text)
        return try JSONDecoder().decode(AgentJSON.self, from: Data(text.utf8))
    }
}
