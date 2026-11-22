import Darwin
import XCTest

@testable import Crest

/// Who an agent is for its approval, and when Crest lets a helper attach: a
/// signed program keeps its own identity, a general interpreter's agent is
/// keyed by the name it gives, and a helper attaches only while agents are on
/// and it speaks this build's link.
@MainActor
final class BrowserAgentIdentityTests: XCTestCase {
    // MARK: - Actions - Identity

    func testAnInterpretersAgentIsKeyedByItsNameAndASignedProgramByItsOwn() {
        let client = AgentClientInfo(name: "Example Agent", title: nil, version: "1.0")
        let interpreter = BrowserAgentPeer.Program(
            identity: AgentIdentity(teamID: nil, signingID: "node", path: "/usr/local/bin/node", client: nil),
            name: "node", signer: nil, path: "/usr/local/bin/node", isInterpreter: true)
        let signed = BrowserAgentPeer.Program(
            identity: AgentIdentity(teamID: "TEAM123456", signingID: "com.example.agent", path: nil, client: nil),
            name: "Example", signer: "Example Developer", path: "/Applications/Example.app", isInterpreter: false)

        let running = interpreter.running(client)
        XCTAssertEqual(running.identity.client, "Example Agent")
        XCTAssertEqual(running.agentName, "Example Agent")
        XCTAssertNotEqual(running.identity, interpreter.running(nil).identity)
        // An interpreter whose agent gives no name stays keyed as itself.
        XCTAssertEqual(
            interpreter.running(AgentClientInfo(name: "", title: nil, version: nil)).identity, interpreter.identity)
        // A signed program vouches for itself, whatever its agent says.
        XCTAssertEqual(signed.running(client).identity, signed.identity)
        XCTAssertEqual(signed.running(client).agentName, "Example")
    }

    // MARK: - Actions - Attaching

    func testAHelperAttachesOnlyWhileAgentsAreOnAndOnThisBuildsLink() throws {
        let fixture = try BrowserAgentFixture()

        try fixture.core.send(SetAgents(isOn: false))
        let whileOff = try Self.link()
        fixture.agents.attach(whileOff, version: AgentLinkRequest.version, client: nil)
        XCTAssertFalse(whileOff.isAttached)

        try fixture.core.send(SetAgents(isOn: true))
        let stale = try Self.link()
        fixture.agents.attach(stale, version: AgentLinkRequest.version + 1, client: nil)
        XCTAssertFalse(stale.isAttached)

        let current = try Self.link()
        fixture.agents.attach(current, version: AgentLinkRequest.version, client: nil)
        XCTAssertTrue(current.isAttached)
    }

    // MARK: - Actions - Support

    /// A link over a socket whose other end is gone, from this process.
    private static func link() throws -> BrowserMacAgents.Link {
        var descriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw POSIXError(.EIO) }
        Darwin.close(descriptors[1])
        let peer = BrowserAgentPeer(helperProcessID: getpid(), agent: nil)
        return BrowserMacAgents.Link(connection: BrowserAgentConnection(descriptor: descriptors[0], peer: peer))
    }
}
