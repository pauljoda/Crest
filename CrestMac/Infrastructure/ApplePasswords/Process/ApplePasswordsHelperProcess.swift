import Foundation
import os

/// The running helper, spoken to over its standard input and output as Apple's
/// Chrome extension does. Crest's main process is its direct parent, which the
/// system requires of a browser that holds the passkey entitlement.
final class ApplePasswordsHelperProcess: ApplePasswordsChannel, @unchecked Sendable {
    // MARK: - Static Variables

    /// The origin Chromium passes a native messaging host as its first argument:
    /// Apple's own extension, which the helper allows.
    static let appleExtensionOrigin = "chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/"

    // MARK: - Types

    private struct State {
        var frames = ApplePasswordsFrameStream()
        var isClosed = false
        var wasTerminatedByCrest = false
        var isInputClosed = false
    }

    // MARK: - Variables

    let events: AsyncStream<ApplePasswordsChannelEvent>
    private let continuation: AsyncStream<ApplePasswordsChannelEvent>.Continuation
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let state = OSAllocatedUnfairLock(initialState: State())
    /// Guards the write end of the pipe, so a write and the close cannot interleave.
    private let writeLock = NSLock()
    /// Serializes reads of the helper's output, so the final drain and a read in progress cannot interleave.
    private let readLock = NSLock()

    /// The only variables the helper is given, copied from Crest's own.
    private static let inheritedEnvironment = ["HOME", "USER", "LOGNAME", "TMPDIR", "PATH"]

    // MARK: - Initializers

    /// Starts the helper. It is a child of this process, never of a helper tool
    /// or XPC service, and its error output is discarded.
    init(executable: URL) throws(ApplePasswordsUnavailability) {
        (events, continuation) = AsyncStream.makeStream(of: ApplePasswordsChannelEvent.self)
        process.executableURL = executable
        process.arguments = [Self.appleExtensionOrigin]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let environment = ProcessInfo.processInfo.environment
        process.environment = Self.inheritedEnvironment.reduce(into: [:]) { copy, name in
            copy[name] = environment[name]
        }
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.terminationHandler = { [weak self] process in
            self?.processDidTerminate(process)
        }
        // A write to a helper that has gone must fail, not raise SIGPIPE in Crest.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            readLock.withLock { receive(handle.availableData) }
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            continuation.finish()
            DiagnosticLog.applePasswords.error("The helper did not start.")
            throw .launchFailed
        }
    }

    // MARK: - Actions - Channel

    func send(_ payload: Data) throws {
        let frame = try ApplePasswordsFrameStream.frame(payload)
        writeLock.lock()
        defer { writeLock.unlock() }
        guard !state.withLock({ $0.isInputClosed }) else { throw ApplePasswordsError.unavailable(.pipeBroken) }
        do {
            try input.fileHandleForWriting.write(contentsOf: frame)
        } catch {
            throw ApplePasswordsError.unavailable(.pipeBroken)
        }
    }

    func terminate() {
        state.withLock { $0.wasTerminatedByCrest = true }
        if process.isRunning { process.terminate() }
        writeLock.lock()
        defer { writeLock.unlock() }
        let wasClosed = state.withLock { state -> Bool in
            defer { state.isInputClosed = true }
            return state.isInputClosed
        }
        if !wasClosed { try? input.fileHandleForWriting.close() }
    }

    // MARK: - Actions - Reading

    private func receive(_ data: Data) {
        guard !data.isEmpty else {
            finishAfterEndOfOutput()
            return
        }
        do {
            let payloads = try state.withLock { try $0.frames.append(data) }
            for payload in payloads { continuation.yield(.frame(payload)) }
        } catch {
            // A malformed length ends the conversation: nothing after it can be trusted.
            DiagnosticLog.applePasswords.error("The helper sent a frame the protocol does not allow.")
            close(with: .malformedReply)
            terminate()
        }
    }

    /// The helper closed its output. A helper that still runs after that is
    /// ended; the exit itself is reported by the termination handler.
    private func finishAfterEndOfOutput() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { terminate() }
    }

    private func processDidTerminate(_ process: Process) {
        let status = process.terminationStatus
        let endedBySignal = process.terminationReason == .uncaughtSignal
        let byCrest = state.withLock { $0.wasTerminatedByCrest }
        // A reply sent just before the exit may still wait in the pipe: deliver it before closing.
        output.fileHandleForReading.readabilityHandler = nil
        readLock.withLock {
            if let remaining = try? output.fileHandleForReading.readToEnd(), !remaining.isEmpty {
                receive(remaining)
            }
        }
        DiagnosticLog.applePasswords.notice(
            "The helper ended with status \(status), by signal \(endedBySignal), at Crest's request \(byCrest)."
        )
        close(with: .terminated(status: status, endedBySignal: endedBySignal))
    }

    private func close(with reason: ApplePasswordsUnavailability) {
        let alreadyClosed = state.withLock { state -> Bool in
            defer { state.isClosed = true }
            return state.isClosed
        }
        guard !alreadyClosed else { return }
        output.fileHandleForReading.readabilityHandler = nil
        continuation.yield(.closed(reason))
        continuation.finish()
    }
}
