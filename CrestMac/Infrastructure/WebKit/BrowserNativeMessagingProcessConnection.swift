import Foundation
import WebKit

@MainActor
final class BrowserNativeMessagingProcessConnection {
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let errorOutput: FileHandle
    private let writes = DispatchQueue(
        label: "com.pauldavis.crest.native-messaging-write"
    )
    private let chunks: AsyncStream<Data>.Continuation
    private var readTask: Task<Void, Never>?
    private var replyTimeoutTask: Task<Void, Never>?
    private var decoder = BrowserNativeMessagingFrameDecoder()
    private var didDisconnect = false
    private let receive: (Any) -> Void
    private let disconnectHandler: (Error) -> Void

    var isHostRunning: Bool { process.isRunning }

    init(
        host: BrowserNativeMessagingHostManifest,
        extensionID: BrowserChromeExtensionID,
        replyTimeout: Duration? = nil,
        receive: @escaping (Any) -> Void,
        disconnect: @escaping (Error) -> Void
    ) throws {
        self.receive = receive
        disconnectHandler = disconnect
        process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        errorOutput = errorPipe.fileHandleForReading
        // A host that dies mid-write must fail the write with EPIPE instead of
        // raising SIGPIPE, which would take the whole browser down with it.
        _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.executableURL = host.executableURL
        process.arguments = [
            "chrome-extension://\(extensionID.rawValue)/"
        ]
        process.currentDirectoryURL = host.executableURL
            .deletingLastPathComponent()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        chunks = continuation
        // One ordered queue of chunks: unstructured per-chunk tasks have no
        // FIFO guarantee between them, and a reordered chunk would corrupt
        // every frame boundary after it.
        output.readabilityHandler = { handle in
            continuation.yield(handle.availableData)
        }
        errorOutput.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.disconnect(
                    error: BrowserNativeMessagingHostError.disconnected
                )
            }
        }
        do {
            try process.run()
        } catch {
            continuation.finish()
            closeHandles()
            throw BrowserNativeMessagingHostError.launchFailed(
                error.localizedDescription
            )
        }
        readTask = Task { @MainActor [weak self] in
            for await chunk in stream {
                guard let self else { return }
                received(chunk)
            }
        }
        guard let replyTimeout else { return }
        replyTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: replyTimeout)
            guard !Task.isCancelled else { return }
            self?.disconnect(
                error: BrowserNativeMessagingHostError.timedOut
            )
        }
    }

    func send(_ message: Any) throws {
        guard !didDisconnect else {
            throw BrowserNativeMessagingHostError.disconnected
        }
        let frame = try BrowserNativeMessagingFrameCodec.encode(message)
        let handle = input
        // Writing blocks once the operating system's pipe buffer fills, so a
        // host that stops draining stdin would otherwise freeze the main
        // actor. One serial queue keeps the protocol's message order.
        writes.async { [weak self] in
            do {
                try handle.write(contentsOf: frame)
            } catch {
                Task { @MainActor in
                    self?.disconnect(error: error)
                }
            }
        }
    }

    func disconnect(
        error: Error = BrowserNativeMessagingHostError.disconnected
    ) {
        guard !didDisconnect else { return }
        didDisconnect = true
        replyTimeoutTask?.cancel()
        replyTimeoutTask = nil
        output.readabilityHandler = nil
        errorOutput.readabilityHandler = nil
        chunks.finish()
        readTask?.cancel()
        readTask = nil
        if process.isRunning { process.terminate() }
        closeHandles()
        disconnectHandler(error)
    }

    private func received(_ data: Data) {
        guard !data.isEmpty else {
            disconnect()
            return
        }
        do {
            let messages = try decoder.append(data)
            if !messages.isEmpty {
                replyTimeoutTask?.cancel()
                replyTimeoutTask = nil
            }
            for message in messages {
                guard !didDisconnect else { return }
                receive(message)
            }
        } catch {
            disconnect(error: error)
        }
    }

    private func closeHandles() {
        // Closing the write end on the same queue keeps it ordered behind any
        // pending write, so no queued frame can land on a reused descriptor.
        let handle = input
        writes.async { try? handle.close() }
        try? output.close()
        try? errorOutput.close()
    }
}
