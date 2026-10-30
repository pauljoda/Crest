import Foundation

/// Owns the one Apple Passwords helper process for the whole launch, shared by
/// every Space: Crest pairs once per launch. Nothing here persists. The
/// session key, identifier and private exponent live in memory and are dropped
/// when the helper pushes a re-login request, a request goes unanswered, the
/// process ends, or Crest stops it.
@MainActor
final class ApplePasswordsHelper: ApplePasswordsCredentialSource {
    // MARK: - Types

    enum State: Equatable, Sendable {
        /// No helper process has been asked for.
        case stopped
        /// The helper cannot be used. This holds until `stop()` or the person asks to pair again.
        case unavailable(ApplePasswordsUnavailability)
        /// The helper is understood but holds no session with Crest.
        case unpaired
        /// The helper shows a code and a challenge waits for it.
        case awaitingCode
        case paired
    }

    /// What a query needs from a paired helper, taken together so an answer
    /// can be checked against the session it was asked over.
    private struct Connection {
        let queue: ApplePasswordsRequestQueue
        let session: ApplePasswordsSecretSession
        let generation: Int
    }

    // MARK: - Static Variables

    private static let codeLength = 6
    /// The number a query carries for a page with no tab. Real tabs count up from 1.
    static let unknownTabNumber = 0

    // MARK: - Variables

    private(set) var state: State = .stopped {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }
    /// Called after every change of `state`.
    var onStateChange: (@MainActor (State) -> Void)?
    /// Called when the helper announces that a one-time code arrived.
    var onOneTimeCodeAvailable: (@MainActor () -> Void)?
    /// Called whenever the process and everything learned from it are dropped,
    /// so what was issued over it can be forgotten too.
    var onProcessEnd: (@MainActor () -> Void)?

    private let launcher: any ApplePasswordsChannelLauncher
    private let clock = ContinuousClock()
    private var capabilities: ApplePasswordsCapabilities?
    private var queue: ApplePasswordsRequestQueue?
    private var channel: (any ApplePasswordsChannel)?
    private var events: Task<Void, Never>?
    private var startup: Task<Void, Never>?
    private var attempt: ApplePasswordsPairingAttempt?
    private var session: ApplePasswordsSecretSession?
    /// The number the running helper knows each Crest tab by. Numbers count up
    /// from 1 and are never reused in a launch. The map is cleared when the
    /// helper process ends, and a tab's entry when the tab closes.
    private var tabNumbers: [UUID: Int] = [:]
    private var lastTabNumber = 0
    /// When the running process was started.
    private var startedAt: ContinuousClock.Instant?
    /// Whether the helper was already let start again after it ended on its own.
    private var hasReconnected = false
    /// How long a process must have run before its ending is met with one restart.
    private let reconnectAfter: Duration
    /// Changes whenever the process or its session is replaced, so an answer
    /// that arrives for an earlier one is not applied to the new one.
    private var generation = 0
    /// Changes whenever pairing starts over, so a hello or proof that arrives
    /// for an earlier attempt is dropped instead of installing a session.
    private var pairingEpoch = 0

    // MARK: - Initializers

    /// - Parameter reconnectAfter: Apple's extension reconnects a helper that
    ///   ends more than five seconds after it started; so does Crest, once.
    init(launcher: any ApplePasswordsChannelLauncher, reconnectAfter: Duration = .seconds(5)) {
        self.launcher = launcher
        self.reconnectAfter = reconnectAfter
    }

    // MARK: - Actions - Lifecycle

    /// Starts the helper and learns what it supports. Does nothing unless the
    /// core's answer for the Space starts the helper, or if the helper is
    /// running, or was found unusable.
    /// - Parameter support: The answer to `ApplePasswordsAvailability`.
    func start(support: ApplePasswordsSupport) async {
        guard support.status.startsHelper else { return }
        if let startup { return await startup.value }
        guard queue == nil, !isUnavailable else { return }
        let task = Task { await launchAndNegotiate() }
        startup = task
        await task.value
        startup = nil
    }

    /// Tells the helper Crest is done, ends it and forgets everything.
    func stop() {
        if channel != nil, let end = try? ApplePasswordsEndMessage.encoded() {
            try? channel?.send(end)
        }
        tearDown()
        state = .stopped
    }

    private func launchAndNegotiate() async {
        let launched: any ApplePasswordsChannel
        do {
            launched = try launcher.launch()
        } catch {
            fail(because: unavailability(of: error))
            return
        }
        let queue = ApplePasswordsRequestQueue(channel: launched)
        startedAt = clock.now
        channel = launched
        self.queue = queue
        let current = generation
        listen(to: queue, generation: current)
        do {
            let reported = try await queue.submit(ApplePasswordsCapabilitiesRequest())
            guard current == generation else { return }
            guard reported.isRecognized else {
                fail(because: .unrecognizedCapabilities)
                return
            }
            capabilities = reported
            state = .unpaired
        } catch {
            settle(after: error, generation: current)
        }
    }

    // MARK: - Actions - Pairing

    /// Asks the helper to show a new six-digit code. Any earlier code stops
    /// working. This is the person's explicit pair action, so a helper that
    /// became unavailable is started afresh first; nothing else retries it.
    func requestPairingCode(support: ApplePasswordsSupport) async throws {
        try require(support)
        leaveUnavailable()
        await start(support: support)
        guard let queue, let capabilities else { throw unavailableError() }
        dropSession()
        state = .unpaired
        pairingEpoch += 1
        let current = generation
        let epoch = pairingEpoch
        do {
            let opening = try ApplePasswordsPairingAttempt.opening(byteEncoding: capabilities.byteEncoding)
            let hello = try await queue.submit(opening.request)
            guard current == generation, epoch == pairingEpoch else { throw ApplePasswordsError.cancelled }
            attempt = try ApplePasswordsPairingAttempt.answered(
                hello,
                client: opening.client,
                byteEncoding: capabilities.byteEncoding,
                at: clock.now
            )
            state = .awaitingCode
        } catch {
            if epoch == pairingEpoch { settle(after: error, generation: current) }
            throw error
        }
    }

    /// Proves the code the person typed. The challenge is spent whatever the
    /// outcome, so a wrong code needs a new one from `requestPairingCode()`.
    /// - Throws: `ApplePasswordsPairingError.wrongCode` for a code that does not match.
    func completePairing(code: String, support: ApplePasswordsSupport) async throws {
        try require(support)
        // A code that cannot be one is refused before the challenge is spent.
        guard code.count == Self.codeLength, code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw ApplePasswordsPairingError.malformedCode
        }
        guard let queue else { throw unavailableError() }
        guard let challenge = attempt else { throw ApplePasswordsPairingError.challengeExpired }
        attempt = nil
        guard challenge.isLive(at: clock.now) else {
            state = .unpaired
            throw ApplePasswordsPairingError.challengeExpired
        }
        let current = generation
        let epoch = pairingEpoch
        do {
            let answer = try challenge.answer(code: code)
            let verification = try await queue.submit(answer.request)
            guard current == generation, epoch == pairingEpoch else { throw ApplePasswordsError.cancelled }
            guard answer.solution.verifies(serverProof: verification.proof) else {
                throw ApplePasswordsPairingError.serverProofMismatch
            }
            session = ApplePasswordsSecretSession(
                identity: challenge.identity,
                sharedKey: answer.solution.sessionKey,
                byteEncoding: challenge.byteEncoding
            )
            state = .paired
        } catch {
            if epoch == pairingEpoch { settle(after: error, generation: current) }
            throw error
        }
    }

    /// Gives up on the code the helper shows, as Apple's extension does when its
    /// pairing popup closes: tells the helper, then answers with an empty code so
    /// it spends the challenge. Does nothing unless a code is waiting.
    ///
    /// Both messages go straight to the channel and nothing waits for the
    /// refusal, so a silent helper cannot time the session out. The refusal,
    /// if it comes, carries the cancelled attempt's session identifier, and a
    /// pairing request ignores replies that carry another one.
    func cancelPairing() {
        guard state == .awaitingCode, let challenge = attempt, let channel else { return }
        attempt = nil
        pairingEpoch += 1
        state = .unpaired
        do {
            try channel.send(ApplePasswordsCancelPairingMessage.encoded())
            try channel.send(challenge.answer(code: "").request.encoded())
        } catch {
            fail(because: unavailability(of: error))
        }
    }

    // MARK: - Actions - Credentials

    func logins(
        for origin: CredentialOrigin,
        tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> ApplePasswordsLoginNamesRequest.Logins {
        let host = try Self.host(of: origin)
        try requireOffer(support)
        let connection = try pairedConnection()
        let request = ApplePasswordsLoginNamesRequest(
            session: connection.session, tabID: tabNumber(for: tab), host: host)
        return try await submit(request, over: connection)
    }

    func password(
        for origin: CredentialOrigin,
        username: String,
        tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> String {
        let host = try Self.host(of: origin)
        try requireOffer(support)
        let connection = try pairedConnection()
        let request = ApplePasswordsPasswordRequest(
            session: connection.session,
            tabID: tabNumber(for: tab),
            host: host,
            username: username
        )
        guard let password = try await submit(request, over: connection) else {
            throw ApplePasswordsError.loginNotFound
        }
        return password
    }

    // MARK: - Actions - One-time codes

    /// Whether the helper said it can fill one-time codes.
    var canFillOneTimeCodes: Bool {
        capabilities?.canFillOneTimeCodes == true
    }

    /// The codes saved for the frame, listed without reading any value that
    /// changes. Throws unless the frame's origin is https, the core's answer
    /// allows the helper and the helper said it fills codes.
    func oneTimeCodes(
        for origin: CredentialOrigin, topLevel: CredentialOrigin, username: String?, tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> [ApplePasswordsOneTimeCode] {
        let host = try Self.host(of: origin)
        let frameURLs = try ApplePasswordsFrameURLs(frame: origin, topLevel: topLevel)
        try requireOneTimeCodes(support)
        let connection = try pairedConnection()
        let request = ApplePasswordsOneTimeCodesRequest(
            session: connection.session, tabID: tabNumber(for: tab), host: host, frameURLs: frameURLs,
            username: username)
        return try await submit(request, over: connection)
    }

    /// Tells the helper the person picked a generated code, and returns the
    /// code that is current now, under the same rules as `oneTimeCodes`.
    func currentOneTimeCode(
        for origin: CredentialOrigin, topLevel: CredentialOrigin, username: String?, domain: String?, tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> String {
        let host = try Self.host(of: origin)
        let frameURLs = try ApplePasswordsFrameURLs(frame: origin, topLevel: topLevel)
        try requireOneTimeCodes(support)
        let connection = try pairedConnection()
        let request = ApplePasswordsFillOneTimeCodeRequest(
            session: connection.session, tabID: tabNumber(for: tab), host: host, frameURLs: frameURLs,
            username: username, domain: domain)
        guard let code = try await submit(request, over: connection) else {
            throw ApplePasswordsError.loginNotFound
        }
        return code
    }

    /// Whether the helper said it can save an account with no username.
    var savesAccountsWithoutUsername: Bool {
        capabilities?.canSaveAccountWithEmptyUserName == true
    }

    /// Offers the account to Apple Passwords, which asks the person to confirm
    /// in its own alert. Create or update is the helper's decision. The result
    /// is "sent", not "saved": the helper may never acknowledge, so the request
    /// waits a few seconds and carries on with the session intact.
    ///
    /// The account is saved for the origin it was captured for, by its host,
    /// and only if the origin is https and the core's answer offers Apple
    /// Passwords. Both are checked before anything is sent. The password
    /// lives only as long as the request does.
    func save(
        _ username: String, _ password: String, for origin: CredentialOrigin, form: ApplePasswordsFormKind,
        tab: UUID?, support: ApplePasswordsSupport
    ) async throws {
        try requireOffer(support)
        _ = try Self.host(of: origin)
        let connection = try pairedConnection()
        let request = try Self.saveRequest(
            username: username, password: password, origin: origin, form: form, tabID: tabNumber(for: tab),
            session: connection.session)
        try await submit(request, over: connection)
    }

    /// The request that offers `username` and `password` for the origin's host.
    /// Throws for an origin that is not https.
    static func saveRequest(
        username: String, password: String, origin: CredentialOrigin, form: ApplePasswordsFormKind,
        tabID: Int, session: ApplePasswordsSecretSession
    ) throws -> ApplePasswordsSaveRequest {
        let host = try host(of: origin)
        return ApplePasswordsSaveRequest(
            session: session, tabID: tabID, host: host, username: username, password: password, form: form)
    }

    private func submit<Request: ApplePasswordsRequest>(
        _ request: Request,
        over connection: Connection
    ) async throws -> Request.Reply {
        do {
            return try await connection.queue.submit(request)
        } catch {
            settle(after: error, generation: connection.generation)
            throw error
        }
    }

    // MARK: - Actions - Connection

    private func pairedConnection() throws -> Connection {
        if case .unavailable(let reason) = state { throw ApplePasswordsError.unavailable(reason) }
        guard let queue, let session, state == .paired else { throw ApplePasswordsError.notPaired }
        return Connection(queue: queue, session: session, generation: generation)
    }

    /// The host a query is about. Only https origins are queried, and only by host.
    private static func host(of origin: CredentialOrigin) throws -> String {
        guard origin.isSecure else { throw ApplePasswordsError.insecureOrigin }
        return origin.host
    }

    /// Reading logins is gated by the stronger answer: Apple Passwords is on offer in the Space.
    private func requireOffer(_ support: ApplePasswordsSupport) throws {
        guard support.status.offersApplePasswords else { throw ApplePasswordsError.notPermitted }
    }

    /// Codes need the stronger answer, and a helper that said it fills them.
    private func requireOneTimeCodes(_ support: ApplePasswordsSupport) throws {
        try requireOffer(support)
        guard canFillOneTimeCodes else { throw ApplePasswordsError.notPermitted }
    }

    /// Starting and pairing are gated by the core's answer for the Space.
    private func require(_ support: ApplePasswordsSupport) throws {
        guard support.status.startsHelper else { throw ApplePasswordsError.notPermitted }
    }

    // MARK: - Actions - Tabs

    /// The number the helper knows `tab` by, given out the first time it is
    /// needed. A page with no tab gets `unknownTabNumber`, which no tab has.
    func tabNumber(for tab: UUID?) -> Int {
        guard let tab else { return Self.unknownTabNumber }
        if let existing = tabNumbers[tab] { return existing }
        lastTabNumber += 1
        tabNumbers[tab] = lastTabNumber
        return lastTabNumber
    }

    /// Whether a helper process is running, paired or not. Tab events and the
    /// launch of the Passwords app go only to a process that is.
    var isRunning: Bool {
        switch state {
        case .unpaired, .awaitingCode, .paired: return channel != nil
        case .stopped, .unavailable: return false
        }
    }

    /// Tells the helper `tab` is in front, as Apple's extension does when a tab
    /// is activated or a window is focused. Does nothing unless the helper is
    /// running; it is never started for this.
    func tabActivated(_ tab: UUID) {
        guard isRunning else { return }
        sendTabEvent(.activated, number: tabNumber(for: tab))
    }

    /// Forgets `tab`'s number and, if the helper had been told about the tab,
    /// tells it the tab closed. The number is not given to another tab.
    func tabClosed(_ tab: UUID) {
        guard let number = tabNumbers.removeValue(forKey: tab), isRunning else { return }
        sendTabEvent(.closed, number: number)
    }

    private func sendTabEvent(_ event: ApplePasswordsTabEvent, number: Int) {
        guard let message = try? ApplePasswordsTabEventMessage.encoded(tabID: number, event: event) else { return }
        // A helper that cannot be written to is reported by its channel, so a failure needs no handling here.
        try? channel?.send(message)
    }

    // MARK: - Actions - Passwords app

    /// Has the helper open the Passwords app on the origin's site. It needs the
    /// helper running but no pairing, and is gated by the core's answer like
    /// starting is. Only an https origin is named, and only by its origin.
    func openPasswordsApp(for origin: CredentialOrigin, support: ApplePasswordsSupport) async throws {
        try require(support)
        let message = try ApplePasswordsLaunchPasswordsAppMessage.encoded(origin: origin)
        await start(support: support)
        guard isRunning, let channel else { throw unavailableError() }
        try channel.send(message)
    }

    // MARK: - Mutators

    private var isUnavailable: Bool {
        if case .unavailable = state { return true }
        return false
    }

    /// Lets an unavailable helper be started again, as if for the first time.
    /// Nothing from the failed run is kept, and the once-per-launch reconnect
    /// allowance is untouched. A start already under way is not affected.
    private func leaveUnavailable() {
        guard isUnavailable else { return }
        tearDown()
        state = .stopped
    }

    private func unavailableError() -> ApplePasswordsError {
        if case .unavailable(let reason) = state { return .unavailable(reason) }
        return .notPaired
    }

    private func unavailability(of error: any Error) -> ApplePasswordsUnavailability {
        if let unavailability = error as? ApplePasswordsUnavailability { return unavailability }
        if case .unavailable(let reason)? = error as? ApplePasswordsError { return reason }
        return .malformedReply
    }

    /// Forgets the session and any challenge. The process, if any, stays.
    private func dropSession() {
        session = nil
        attempt = nil
    }

    /// Ends the process and forgets everything it was paired with.
    private func tearDown() {
        generation += 1
        dropSession()
        capabilities = nil
        tabNumbers = [:]
        startedAt = nil
        onProcessEnd?()
        events?.cancel()
        events = nil
        channel?.terminate()
        channel = nil
        if let queue { Task { await queue.shutdown() } }
        queue = nil
    }

    /// The helper process ended on its own. Apple's extension reconnects when
    /// that is more than five seconds after the process started; Crest does
    /// the same once per launch. A reconnect forgets the session and every
    /// number and leaves the helper stopped, so the next use starts it
    /// through the core's answer for the Space, and the person pairs again.
    /// An earlier ending, or a second one, makes the helper unavailable.
    private func processEnded(because reason: ApplePasswordsUnavailability) {
        guard !hasReconnected, capabilities != nil, let startedAt, clock.now - startedAt > reconnectAfter else {
            fail(because: reason)
            return
        }
        hasReconnected = true
        DiagnosticLog.applePasswords.notice("The helper ended; it can start again once.")
        tearDown()
        state = .stopped
    }

    private func fail(because reason: ApplePasswordsUnavailability) {
        DiagnosticLog.applePasswords.notice("The helper is unavailable.")
        tearDown()
        state = .unavailable(reason)
    }

    /// Brings `state` in line with a failed call, unless the process or session has since changed.
    private func settle(after error: any Error, generation callGeneration: Int) {
        guard callGeneration == generation else { return }
        if error is ApplePasswordsPairingError {
            dropSession()
            state = .unpaired
            return
        }
        guard let error = error as? ApplePasswordsError else { return }
        switch error {
        case .unavailable(.timedOut):
            // The queue gave up on a request: end the session rather than risk a mismatched reply.
            tearDown()
            state = .unpaired
        case .unavailable(let reason):
            if case .terminated = reason {
                processEnded(because: reason)
            } else {
                fail(because: reason)
            }
        case .notPaired, .malformedReply:
            // The helper lost the session, or a reply no longer opens with our key: it is out of step.
            dropSession()
            state = .unpaired
        case .queryFailed, .loginNotFound, .cancelled, .insecureOrigin, .randomnessUnavailable,
            .notPermitted:
            break
        }
    }

    // MARK: - Actions - Events

    private func listen(to queue: ApplePasswordsRequestQueue, generation current: Int) {
        events = Task { [weak self] in
            for await event in queue.events {
                guard let self, self.generation == current else { return }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: ApplePasswordsRequestQueue.Event) {
        switch event {
        case .push(let push) where !push.endsSession:
            onOneTimeCodeAvailable?()
        case .push:
            dropSession()
            state = .unpaired
        case .invalidated:
            tearDown()
            state = .unpaired
        case .closed(let reason):
            guard case .terminated = reason else {
                fail(because: reason)
                return
            }
            processEnded(because: reason)
        }
    }
}
