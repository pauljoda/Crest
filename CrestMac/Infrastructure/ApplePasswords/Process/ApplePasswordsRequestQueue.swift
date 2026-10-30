import Foundation

/// Sends requests to the helper one at a time and matches each reply to its
/// request by command, because replies carry no other identifier.
///
/// Requests run first in, first out with one in flight. A request that times
/// out leaves the queue unable to tell a late reply from the next request's,
/// so the queue stops accepting requests and reports `invalidated`; the owner
/// ends the session rather than risk handing one caller another's answer.
///
/// A request that tolerates silence (`ApplePasswordsRequest.silentReply`) is the
/// exception: when its wait ends it resolves as sent, the session stays, and
/// its command is remembered so a late acknowledgement is swallowed.
///
/// A caller that is cancelled while its request is in flight gets `cancelled`
/// at once, but the request stays in flight: the next request waits for its
/// reply, which is then discarded. That keeps replies matched, and a cancelled
/// caller (the person leaving during Touch ID) does not end the session.
actor ApplePasswordsRequestQueue {
    // MARK: - Types

    enum Event: Sendable {
        /// The helper announced something on its own.
        case push(ApplePasswordsPush)
        /// The queue can no longer match replies and takes no more requests.
        case invalidated
        /// The helper is gone or broke the protocol.
        case closed(ApplePasswordsUnavailability)
    }

    private struct InFlight {
        let id: UUID
        let command: ApplePasswordsCommand
        /// Whether a reply with the command may answer the request.
        let accepts: @Sendable (ApplePasswordsInboundEnvelope) -> Bool
        /// Nil once the caller has been cancelled; the reply is then discarded.
        var continuation: CheckedContinuation<ApplePasswordsInboundEnvelope?, any Error>?
        /// Whether the end of the wait resolves the request as sent instead of giving up on it.
        let toleratesSilence: Bool
        var timeout: Task<Void, Never>?
    }

    private struct TurnWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    // MARK: - Variables

    nonisolated let events: AsyncStream<Event>
    private let eventContinuation: AsyncStream<Event>.Continuation
    private let channel: any ApplePasswordsChannel
    private var reading: Task<Void, Never>?
    private var inFlight: InFlight?
    private var isBusy = false
    private var turnWaiters: [TurnWaiter] = []
    /// Commands whose request ended in silence. A reply that arrives later for
    /// one of them is an acknowledgement that carries no data, and is swallowed.
    private var silentCommands: Set<ApplePasswordsCommand> = []
    /// Once set, every request fails with it.
    private var failure: ApplePasswordsError?

    // MARK: - Initializers

    init(channel: any ApplePasswordsChannel) {
        self.channel = channel
        (events, eventContinuation) = AsyncStream.makeStream(of: Event.self)
    }

    // MARK: - Actions - Requests

    /// Runs `request` after those before it and returns what its reply means.
    func submit<Request: ApplePasswordsRequest>(_ request: Request) async throws -> Request.Reply {
        startReading()
        try await acquireTurn()
        // From here the turn is released when the request leaves the helper's hands.
        let payload: Data
        do {
            if let failure { throw failure }
            guard !Task.isCancelled else { throw ApplePasswordsError.cancelled }
            payload = try request.encoded()
        } catch {
            releaseTurn()
            throw error
        }
        let envelope = try await exchange(
            payload, command: request.command, timeout: request.timeout,
            toleratesSilence: request.silentReply != nil, accepts: { request.accepts($0) })
        guard let envelope else {
            // Only a request that tolerates silence resolves without a reply.
            guard let silent = request.silentReply else { throw ApplePasswordsError.unavailable(.timedOut) }
            return silent
        }
        return try request.reply(from: envelope)
    }

    /// Ends the queue: pending requests fail and nothing more is read.
    func shutdown() {
        fail(with: .cancelled)
        reading?.cancel()
        eventContinuation.finish()
    }

    /// Reads the channel's events from the first request on. What arrives
    /// earlier waits in the channel's stream.
    private func startReading() {
        guard reading == nil else { return }
        let events = channel.events
        reading = Task { [weak self] in
            for await event in events {
                await self?.receive(event)
            }
        }
    }

    // MARK: - Actions - Turns

    private func acquireTurn() async throws {
        guard isBusy else {
            isBusy = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                turnWaiters.append(TurnWaiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiting(id) }
        }
    }

    private func releaseTurn() {
        guard !turnWaiters.isEmpty else {
            isBusy = false
            return
        }
        turnWaiters.removeFirst().continuation.resume()
    }

    private func cancelWaiting(_ id: UUID) {
        guard let index = turnWaiters.firstIndex(where: { $0.id == id }) else { return }
        turnWaiters.remove(at: index).continuation.resume(throwing: ApplePasswordsError.cancelled)
    }

    // MARK: - Actions - Exchange

    private func exchange(
        _ payload: Data,
        command: ApplePasswordsCommand,
        timeout: Duration,
        toleratesSilence: Bool,
        accepts: @escaping @Sendable (ApplePasswordsInboundEnvelope) -> Bool
    ) async throws -> ApplePasswordsInboundEnvelope? {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                inFlight = InFlight(
                    id: id, command: command, accepts: accepts, continuation: continuation,
                    toleratesSilence: toleratesSilence)
                do {
                    try channel.send(payload)
                } catch {
                    resolve(id, with: .failure(error))
                    return
                }
                inFlight?.timeout = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    await self?.abandon(id, because: .unavailable(.timedOut))
                }
            }
        } onCancel: {
            Task { await self.detach(id) }
        }
    }

    /// Ends the request in flight, returns the turn and hands a waiting caller the result.
    private func resolve(_ id: UUID, with result: Result<ApplePasswordsInboundEnvelope?, any Error>) {
        guard let pending = inFlight, pending.id == id else { return }
        inFlight = nil
        pending.timeout?.cancel()
        pending.continuation?.resume(with: result)
        releaseTurn()
    }

    /// The caller of the request in flight was cancelled: it stops waiting,
    /// and the request keeps its place until the helper answers or times out.
    private func detach(_ id: UUID) {
        guard let pending = inFlight, pending.id == id, let continuation = pending.continuation else { return }
        inFlight?.continuation = nil
        continuation.resume(throwing: ApplePasswordsError.cancelled)
    }

    /// A request's wait ended while the helper may still answer it. A request
    /// that tolerates silence is simply sent: the session stays, and the
    /// command is remembered so its late acknowledgement is swallowed.
    private func abandon(_ id: UUID, because error: ApplePasswordsError) {
        guard let pending = inFlight, pending.id == id else { return }
        if pending.toleratesSilence {
            silentCommands.insert(pending.command)
            resolve(id, with: .success(nil))
            return
        }
        resolve(id, with: .failure(error))
        invalidate()
    }

    private func invalidate() {
        guard failure == nil else { return }
        failure = .unavailable(.timedOut)
        DiagnosticLog.applePasswords.notice("A helper request was given up on, so the session is dropped.")
        eventContinuation.yield(.invalidated)
        channel.terminate()
    }

    private func fail(with error: ApplePasswordsError) {
        if failure == nil { failure = error }
        if let pending = inFlight { resolve(pending.id, with: .failure(error)) }
    }

    // MARK: - Actions - Receiving

    private func receive(_ event: ApplePasswordsChannelEvent) {
        switch event {
        case .frame(let payload): receive(frame: payload)
        case .closed(let reason):
            fail(with: .unavailable(reason))
            eventContinuation.yield(.closed(reason))
        }
    }

    private func receive(frame payload: Data) {
        guard let envelope = try? JSONDecoder().decode(ApplePasswordsInboundEnvelope.self, from: payload) else {
            DiagnosticLog.applePasswords.error("The helper sent a message that is not valid JSON.")
            fail(with: .unavailable(.malformedReply))
            eventContinuation.yield(.closed(.malformedReply))
            channel.terminate()
            return
        }
        guard let command = envelope.command else {
            DiagnosticLog.applePasswords.notice("Ignored a helper message numbered \(envelope.number).")
            return
        }
        if command.isUnsolicited {
            if let push = command.push { receive(push: push) }
            return
        }
        guard let pending = inFlight, pending.command == command else {
            if silentCommands.contains(command) {
                // The late acknowledgement of a request that ended in silence. It has a
                // different command from any other kind of request, so it can never
                // answer one. If a later request has the same command (a second save), the
                // acknowledgement may end that request early: it carries no data, so
                // the early end cannot hand that caller a wrong answer, and the
                // request's own acknowledgement is swallowed here when it arrives.
                DiagnosticLog.applePasswords.notice("Swallowed a late acknowledgement numbered \(command.number).")
            } else {
                DiagnosticLog.applePasswords.notice("Dropped an unexpected helper reply numbered \(command.number).")
            }
            return
        }
        guard pending.accepts(envelope) else {
            DiagnosticLog.applePasswords.notice(
                "Dropped a helper reply numbered \(command.number) meant for another request.")
            return
        }
        if pending.continuation == nil {
            DiagnosticLog.applePasswords.notice(
                "Discarded the reply to a cancelled request numbered \(command.number).")
        }
        resolve(pending.id, with: .success(envelope))
    }

    private func receive(push: ApplePasswordsPush) {
        DiagnosticLog.applePasswords.notice("The helper announced \(push.name).")
        if push.endsSession, let pending = inFlight {
            // Its reply, if one comes, cannot be told from the next request's.
            resolve(pending.id, with: .failure(ApplePasswordsError.notPaired))
            invalidate()
        }
        eventContinuation.yield(.push(push))
    }
}
