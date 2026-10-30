import XCTest

@testable import Crest

/// The helper's gates and the request queue's matching rules, against a fake
/// channel. No process is started.
@MainActor
final class ApplePasswordsHelperTests: XCTestCase {
    func testTheLauncherRefusesAnIsolatedLaunch() {
        let isolated = BrowserLaunchEnvironment(values: ["CREST_ISOLATED_SESSION": "1"], isXCTestRuntime: false)
        let launcher = ApplePasswordsProcessLauncher(launchEnvironment: isolated)

        XCTAssertThrowsError(try launcher.launch()) {
            XCTAssertEqual($0 as? ApplePasswordsUnavailability, .isolatedLaunch)
        }
    }

    func testTheHelperDoesNothingUnlessTheCoreStartsIt() async throws {
        let helper = ApplePasswordsHelper(launcher: RefusingLauncher())
        let origin = CredentialOrigin(scheme: "https", host: "example.com", port: 443)
        let refused = ApplePasswordsTestSupport.refused

        await helper.start(support: refused)
        XCTAssertEqual(helper.state, .stopped)

        await assertNotPermitted { try await helper.requestPairingCode(support: refused) }
        await assertNotPermitted { try await helper.completePairing(code: "123456", support: refused) }
        await assertNotPermitted { _ = try await helper.logins(for: origin, tab: nil, support: refused) }
        await assertNotPermitted {
            _ = try await helper.password(for: origin, username: "ada", tab: nil, support: refused)
        }
        XCTAssertEqual(helper.state, .stopped)

        // Pairing may go on while the answer is "pairing required", but reading logins needs "available".
        let pairing = ApplePasswordsTestSupport.pairing
        XCTAssertFalse(pairing.status.offersApplePasswords)
        await assertNotPermitted { _ = try await helper.logins(for: origin, tab: nil, support: pairing) }
        await assertNotPermitted {
            _ = try await helper.password(for: origin, username: "ada", tab: nil, support: pairing)
        }
    }

    func testOnlyAnExplicitPairRequestStartsAnUnavailableHelperAgain() async throws {
        let channel = FakeApplePasswordsChannel()
        channel.script = ApplePasswordsPairingScript.respond(on: channel)
        let launcher = FailingThenWorkingLauncher(failures: 2, channel: channel)
        let helper = ApplePasswordsHelper(launcher: launcher)
        let support = ApplePasswordsTestSupport.pairing

        await helper.start(support: support)
        XCTAssertEqual(helper.state, .unavailable(.launchFailed))
        await helper.start(support: support)
        XCTAssertEqual(launcher.launches, 1, "Starting on its own never retries.")

        // The retry fails too: it is unavailable again, and the person may click again.
        await assertUnavailable { try await helper.requestPairingCode(support: support) }
        XCTAssertEqual(launcher.launches, 2)
        XCTAssertEqual(helper.state, .unavailable(.launchFailed))

        try await helper.requestPairingCode(support: support)
        XCTAssertEqual(launcher.launches, 3)
        XCTAssertEqual(helper.state, .awaitingCode)

        // A click while pairing is under way reuses the one process.
        try await helper.requestPairingCode(support: support)
        XCTAssertEqual(launcher.launches, 3)
        helper.stop()

        // The core's answer still rules: a refused answer never retries.
        let refused = ApplePasswordsHelper(launcher: FailingThenWorkingLauncher(failures: 1, channel: channel))
        await refused.start(support: support)
        await assertNotPermitted { try await refused.requestPairingCode(support: ApplePasswordsTestSupport.refused) }
        XCTAssertEqual(refused.state, .unavailable(.launchFailed))
    }

    func testAMalformedCodeDoesNotSpendTheChallenge() async throws {
        let channel = FakeApplePasswordsChannel()
        channel.script = ApplePasswordsPairingScript.respond(on: channel)
        let helper = ApplePasswordsHelper(launcher: FakeApplePasswordsLauncher(channel: channel))
        let support = ApplePasswordsTestSupport.pairing

        try await helper.requestPairingCode(support: support)
        XCTAssertEqual(helper.state, .awaitingCode)
        let sentBefore = channel.sentCount

        for malformed in ["12345", "1234567", "12345a", "١٢٣٤٥٦", ""] {
            do {
                try await helper.completePairing(code: malformed, support: support)
                XCTFail("A code that is not six digits must be refused.")
            } catch {
                XCTAssertEqual(error as? ApplePasswordsPairingError, .malformedCode)
            }
        }
        XCTAssertEqual(channel.sentCount, sentBefore, "Nothing reaches the helper for a malformed code.")
        XCTAssertEqual(helper.state, .awaitingCode)

        // The same challenge still answers a well-formed code.
        do {
            try await helper.completePairing(code: "123456", support: support)
            XCTFail("The fake helper refuses every code.")
        } catch {
            XCTAssertEqual(error as? ApplePasswordsPairingError, .wrongCode)
        }
        XCTAssertEqual(channel.sentCount, sentBefore + 1)
        XCTAssertEqual(helper.state, .unpaired)
        helper.stop()
    }

    func testCancellingPairingTellsTheHelperThenSpendsTheChallengeWithAnEmptyCode() async throws {
        let channel = FakeApplePasswordsChannel()
        channel.script = ApplePasswordsPairingScript.respond(on: channel)
        let helper = ApplePasswordsHelper(launcher: FakeApplePasswordsLauncher(channel: channel))
        let support = ApplePasswordsTestSupport.pairing

        helper.cancelPairing()
        XCTAssertEqual(channel.sentCount, 0, "With no code waiting there is nothing to cancel.")

        try await helper.requestPairingCode(support: support)
        let sentBefore = channel.sentCount
        helper.cancelPairing()

        let sent = channel.sentPayloads.dropFirst(sentBefore)
        XCTAssertEqual(sent.count, 2)
        let cancel = try XCTUnwrap(JSONSerialization.jsonObject(with: sent[sentBefore]) as? [String: Any])
        XCTAssertEqual(cancel["cmd"] as? Int, 19)
        let proof = try XCTUnwrap(JSONSerialization.jsonObject(with: sent[sentBefore + 1]) as? [String: Any])
        XCTAssertEqual(proof["cmd"] as? Int, 2)
        XCTAssertEqual(helper.state, .unpaired)

        // The refusal of the empty code may arrive after pairing starts again; it must not answer the new hello.
        try await helper.requestPairingCode(support: support)
        XCTAssertEqual(helper.state, .awaitingCode)
        helper.stop()
    }

    func testPairingStartedAgainDiscardsTheEarlierProof() async throws {
        let channel = FakeApplePasswordsChannel()
        channel.script = ApplePasswordsPairingScript.respond(on: channel, answersProofs: false)
        let helper = ApplePasswordsHelper(launcher: FakeApplePasswordsLauncher(channel: channel))
        let support = ApplePasswordsTestSupport.pairing
        try await helper.requestPairingCode(support: support)

        let proof = Task { try await helper.completePairing(code: "123456", support: support) }
        await waitUntil { channel.sentCount == 3 }
        let restarted = Task { try await helper.requestPairingCode(support: support) }
        await waitUntil { helper.state == .unpaired }

        // The helper accepts the first proof, but pairing has started over.
        let identity = try XCTUnwrap(channel.lastIdentity)
        let accepted = try JSONSerialization.data(withJSONObject: ["TID": identity, "MSG": 3, "HAMK": "00"])
        channel.deliver(#"{"cmd":2,"payload":{"PAKE":"\#(accepted.base64EncodedString())"}}"#)
        do {
            try await proof.value
            XCTFail("An earlier proof must not pair.")
        } catch {
            XCTAssertEqual(error as? ApplePasswordsError, .cancelled)
        }
        try await restarted.value
        XCTAssertEqual(helper.state, .awaitingCode)
        helper.stop()
    }

    func testACancelledCallerDetachesAndItsLateReplyIsDiscarded() async throws {
        let channel = FakeApplePasswordsChannel()
        let queue = ApplePasswordsRequestQueue(channel: channel)
        let first = Task { try await queue.submit(ApplePasswordsCapabilitiesRequest()) }
        await waitUntil { channel.sentCount == 1 }
        let second = Task { try await queue.submit(ApplePasswordsCapabilitiesRequest()) }

        first.cancel()
        do {
            _ = try await first.value
            XCTFail("A cancelled caller gets no reply.")
        } catch {
            XCTAssertEqual(error as? ApplePasswordsError, .cancelled)
        }
        // The cancelled request is still in flight, so the next one waits for it.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(channel.sentCount, 1)

        channel.deliver(#"{"cmd":14,"capabilities":{"shouldUseBase64":true}}"#)
        await waitUntil { channel.sentCount == 2 }

        channel.deliver(#"{"cmd":14,"capabilities":{"shouldUseBase64":false}}"#)
        let capabilities = try await second.value
        XCTAssertEqual(capabilities.shouldUseBase64, false, "The late reply went to nobody.")
        channel.terminate()
        await queue.shutdown()
    }

    func testASaveIsRefusedBeforeAnythingIsSent() async {
        let helper = ApplePasswordsHelper(launcher: RefusingLauncher())
        let secure = CredentialOrigin(scheme: "https", host: "example.com", port: 443)
        let insecure = CredentialOrigin(scheme: "http", host: "example.com", port: 80)

        // The core does not offer Apple Passwords, even to a Space that is still pairing.
        for support in [ApplePasswordsTestSupport.refused, ApplePasswordsTestSupport.pairing] {
            await assertNotPermitted {
                try await helper.save("ada", "secret", for: secure, form: .signIn, tab: nil, support: support)
            }
        }
        do {
            try await helper.save(
                "ada", "secret", for: insecure, form: .signIn, tab: nil, support: ApplePasswordsTestSupport.available)
            XCTFail("Only an https origin is saved.")
        } catch {
            XCTAssertEqual(error as? ApplePasswordsError, .insecureOrigin)
        }
        XCTAssertEqual(helper.state, .stopped, "Nothing started the helper, so nothing was sent.")
    }

    func testASaveNamesTheCapturedOriginsHostAndNothingElse() async throws {
        let session = ApplePasswordsSecretSession(
            identity: "0x00112233445566778899aabbccddeeff", sharedKey: Data(repeating: 0x42, count: 32),
            byteEncoding: .hexadecimal)
        let origin = CredentialOrigin(scheme: "https", host: "accounts.crest.test", port: 8443)
        XCTAssertThrowsError(
            try ApplePasswordsHelper.saveRequest(
                username: "ada", password: "secret",
                origin: CredentialOrigin(scheme: "http", host: "accounts.crest.test", port: 80), form: .signUp,
                tabID: 1, session: session)
        ) { XCTAssertEqual($0 as? ApplePasswordsError, .insecureOrigin) }

        let request = try ApplePasswordsHelper.saveRequest(
            username: "ada", password: "secret", origin: origin, form: .signUp, tabID: 1, session: session)
        let channel = FakeApplePasswordsChannel()
        let queue = ApplePasswordsRequestQueue(channel: channel)
        let sending = Task { try? await queue.submit(request) }
        await waitUntil { channel.sentCount == 1 }

        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(channel.lastSent)) as? [String: Any])
        XCTAssertEqual(envelope["cmd"] as? Int, 6)
        XCTAssertNil(envelope["url"], "A save names its site only inside the sealed body.")
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(try XCTUnwrap(envelope["payload"] as? String).utf8))
                as? [String: Any])
        let sealed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(try XCTUnwrap(payload["SMSG"] as? String).utf8))
                as? [String: Any])
        let outbound = try ApplePasswordsByteEncoding.hexadecimal.bytes(from: try XCTUnwrap(sealed["SDATA"] as? String))
        let nonce = outbound.suffix(ApplePasswordsSecretSession.nonceLength)
        let opened = try session.open(nonce + outbound.dropLast(ApplePasswordsSecretSession.nonceLength))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: opened) as? [String: Any])
        XCTAssertEqual(fields["NURL"] as? String, "accounts.crest.test")
        XCTAssertEqual(fields["NUSR"] as? String, "ada")
        channel.terminate()
        await queue.shutdown()
        _ = await sending.value
    }

    func testARequestThatToleratesSilenceResolvesAsSentAndItsLateAcknowledgementIsSwallowed() async throws {
        let channel = FakeApplePasswordsChannel()
        let queue = ApplePasswordsRequestQueue(channel: channel)
        let invalidated = InvalidationFlag()
        let watching = Task {
            for await event in queue.events {
                if case .invalidated = event { invalidated.raise() }
            }
        }

        // Nobody acknowledges the save, yet the caller carries on and the session survives.
        try await queue.submit(SilentSaveRequest())
        XCTAssertEqual(channel.sentCount, 1)

        // Another kind of request is in flight when the save's late acknowledgement arrives.
        let capabilities = Task { try await queue.submit(ApplePasswordsCapabilitiesRequest()) }
        await waitUntil { channel.sentCount == 2 }
        channel.deliver(#"{"cmd":6}"#)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(channel.sentCount, 2)

        // The capabilities request was not resolved by it: its own reply still arrives.
        channel.deliver(#"{"cmd":14,"capabilities":{"shouldUseBase64":true}}"#)
        let reported = try await capabilities.value
        XCTAssertEqual(reported.shouldUseBase64, true)
        XCTAssertFalse(invalidated.isRaised)

        // A request that does not tolerate silence still gives the session up.
        do {
            try await queue.submit(UnansweredRequest())
            XCTFail("Silence is a failure for a request that does not tolerate it.")
        } catch {
            XCTAssertEqual(error as? ApplePasswordsError, .unavailable(.timedOut))
        }
        channel.terminate()
        await queue.shutdown()
        watching.cancel()
    }

    // MARK: - Fixtures

    private func assertNotPermitted(
        _ work: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await work()
            XCTFail("The core did not allow the helper.", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ApplePasswordsError, .notPermitted, file: file, line: line)
        }
    }

    private func assertUnavailable(_ work: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line)
        async
    {
        do {
            try await work()
            XCTFail("The helper should have stayed unavailable.", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ApplePasswordsError, .unavailable(.launchFailed), file: file, line: line)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Answers the core would give, built here because app code never builds one.
enum ApplePasswordsTestSupport {
    static let available = ApplePasswordsSupport(status: .available, offersToTurnOffExtension: false)
    static let pairing = ApplePasswordsSupport(status: .pairingRequired, offersToTurnOffExtension: false)
    static let refused = ApplePasswordsSupport(status: .turnedOff, offersToTurnOffExtension: false)
}

/// A launcher that fails the test if anything asks it to start a helper.
struct RefusingLauncher: ApplePasswordsChannelLauncher {
    func launch() throws -> any ApplePasswordsChannel {
        XCTFail("No helper may be launched.")
        throw ApplePasswordsUnavailability.launchFailed
    }
}

/// A launcher whose first launches fail, counting every attempt.
final class FailingThenWorkingLauncher: ApplePasswordsChannelLauncher, @unchecked Sendable {
    private(set) var launches = 0
    private let failures: Int
    private let channel: FakeApplePasswordsChannel

    init(failures: Int, channel: FakeApplePasswordsChannel) {
        self.failures = failures
        self.channel = channel
    }

    func launch() throws -> any ApplePasswordsChannel {
        launches += 1
        if launches <= failures { throw ApplePasswordsUnavailability.launchFailed }
        return channel
    }
}

struct FakeApplePasswordsLauncher: ApplePasswordsChannelLauncher {
    let channel: FakeApplePasswordsChannel

    func launch() throws -> any ApplePasswordsChannel { channel }
}

final class FakeApplePasswordsChannel: ApplePasswordsChannel, @unchecked Sendable {
    let events: AsyncStream<ApplePasswordsChannelEvent>
    /// Called with each payload Crest sends, to answer it.
    var script: (@Sendable (Data) -> Void)?
    private let continuation: AsyncStream<ApplePasswordsChannelEvent>.Continuation
    private let lock = NSLock()
    private var sent: [Data] = []
    private var identity: String?

    init() {
        (events, continuation) = AsyncStream.makeStream(of: ApplePasswordsChannelEvent.self)
    }

    /// The session identifier of the latest handshake message Crest sent.
    var lastIdentity: String? {
        lock.withLock { identity }
    }

    func record(identity: String) {
        lock.withLock { self.identity = identity }
    }

    var sentCount: Int {
        lock.withLock { sent.count }
    }

    var sentPayloads: [Data] {
        lock.withLock { sent }
    }

    /// The latest payload Crest sent.
    var lastSent: Data? {
        lock.withLock { sent.last }
    }

    func send(_ payload: Data) throws {
        lock.withLock { sent.append(payload) }
        script?(payload)
    }

    func terminate() {
        continuation.finish()
    }

    func deliver(_ json: String) {
        continuation.yield(.frame(Data(json.utf8)))
    }
}

/// A helper that reports capabilities, issues a challenge and refuses every code.
enum ApplePasswordsPairingScript {
    static func respond(
        on channel: FakeApplePasswordsChannel,
        answersProofs: Bool = true
    ) -> @Sendable (Data) -> Void {
        { [unowned channel] payload in
            guard let message = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                let command = message["cmd"] as? Int
            else { return }
            switch command {
            case 14:
                channel.deliver(#"{"cmd":14,"capabilities":{"secretSessionVersion":1}}"#)
            case 2:
                let inner = (message["msg"] as? String).flatMap {
                    try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
                }
                let step = (inner?["PAKE"] as? String).flatMap { Data(base64Encoded: $0) }
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let identity = step?["TID"] as? String ?? ""
                channel.record(identity: identity)
                if inner?["QID"] as? String != "m0" && !answersProofs { return }
                let answer: [String: Any] =
                    inner?["QID"] as? String == "m0"
                    ? ["TID": identity, "MSG": 1, "PROTO": 1, "B": "0x02", "s": "0x0102"]
                    : ["TID": identity, "MSG": 3, "ErrCode": 1]
                let pake = (try? JSONSerialization.data(withJSONObject: answer))?.base64EncodedString() ?? ""
                channel.deliver(#"{"cmd":2,"payload":{"PAKE":"\#(pake)"}}"#)
            default:
                break
            }
        }
    }
}

/// A save with a short wait, so the test need not sit through the real three seconds.
private struct SilentSaveRequest: ApplePasswordsRequest {
    typealias Reply = Void

    var command: ApplePasswordsCommand { .setPassword }
    var timeout: Duration { .milliseconds(100) }
    var silentReply: Void? { () }

    func encoded() throws -> Data { Data(#"{"cmd":6}"#.utf8) }
    func reply(from envelope: ApplePasswordsInboundEnvelope) throws {}
}

/// A request that expects an answer and gets none within a short wait.
private struct UnansweredRequest: ApplePasswordsRequest {
    typealias Reply = Void

    var command: ApplePasswordsCommand { .getPassword }
    var timeout: Duration { .milliseconds(100) }

    func encoded() throws -> Data { Data(#"{"cmd":5}"#.utf8) }
    func reply(from envelope: ApplePasswordsInboundEnvelope) throws {}
}

private final class InvalidationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    var isRaised: Bool { lock.withLock { raised } }

    func raise() { lock.withLock { raised = true } }
}
