import Darwin
import Foundation

/// The program at the other end of an automation connection, as the kernel
/// reported it when the program connected: its process and the path of the
/// executable it runs.
struct BrowserAutomationPeer: Sendable {
    let processID: pid_t
    let path: String
}

/// The Unix domain socket local tools connect to. Only the person's own user
/// may reach it: the socket file lets its owner alone connect, and a
/// connection from any other user is closed before anything is read from it.
/// Connections are accepted on a queue of the listener's own and handed to
/// `connected` there.
final class BrowserAutomationListener: @unchecked Sendable {
    // MARK: - Types

    enum Failure: Error, Equatable {
        /// Another running Crest answers at the path.
        case inUse
        /// Something other than a socket is at the path.
        case occupied
        /// The system refused `operation` with `code`.
        case system(operation: String, code: Int32)
    }

    /// A file by its device and inode, which tells the socket this listener
    /// bound from one a later launch bound at the same path.
    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    // MARK: - Variables

    let path: String
    private let queue = DispatchQueue(label: "com.pauldavis.crest.automation.listener")
    private let connected: @Sendable (BrowserAutomationConnection) -> Void
    /// What watches the listening socket while the listener runs, and what
    /// its cancellation signals once the socket is closed and removed. Its
    /// owner starts and stops the listener on one thread.
    private var source: DispatchSourceRead?
    private var closed: DispatchSemaphore?

    /// How long `stop` waits for the socket to close.
    private static let closeTimeout = DispatchTimeInterval.seconds(2)

    // MARK: - Initializers

    init(path: String, connected: @escaping @Sendable (BrowserAutomationConnection) -> Void) {
        self.path = path
        self.connected = connected
    }

    deinit {
        source?.cancel()
    }

    // MARK: - Actions - Lifecycle

    /// Binds the socket and starts accepting connections. A socket a Crest
    /// that quit without removing it left behind is replaced; one a running
    /// Crest still answers is not.
    func start() throws(Failure) {
        guard source == nil else { return }
        let descriptor = try bind()
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        let path = path
        let identity = Self.identity(of: path)
        let closed = DispatchSemaphore(value: 0)
        source.setEventHandler { [weak self] in self?.acceptWaiting(on: descriptor) }
        source.setCancelHandler {
            Darwin.close(descriptor)
            // Remove the socket only while it is still the one this listener bound.
            if let identity, Self.identity(of: path) == identity { unlink(path) }
            closed.signal()
        }
        self.source = source
        self.closed = closed
        source.resume()
    }

    /// Stops accepting connections and removes the socket before it returns,
    /// so the path can be bound again at once. Connections already made stay
    /// open until their owner closes them.
    func stop() {
        guard let source, let closed else { return }
        self.source = nil
        self.closed = nil
        // The cancellation runs on the listener's own queue, never the
        // caller's.
        source.cancel()
        _ = closed.wait(timeout: .now() + Self.closeTimeout)
    }

    // MARK: - Actions - Connections

    private func acceptWaiting(on descriptor: Int32) {
        while true {
            let client = Darwin.accept(descriptor, nil, nil)
            guard client >= 0 else { return }
            guard let peer = Self.peer(of: client) else {
                Darwin.close(client)
                continue
            }
            connected(BrowserAutomationConnection(descriptor: client, peer: peer))
        }
    }

    /// The program at the other end of `descriptor`, or nil when it runs as
    /// another user or the kernel cannot say what it runs.
    private static func peer(of descriptor: Int32) -> BrowserAutomationPeer? {
        var user: uid_t = 0
        var group: gid_t = 0
        guard getpeereid(descriptor, &user, &group) == 0, user == getuid() else { return nil }
        var processID: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &processID, &length) == 0, processID > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(processID, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return BrowserAutomationPeer(processID: processID, path: String(decoding: path, as: UTF8.self))
    }

    // MARK: - Mutators

    /// A listening socket bound at `path`, readable and writable by its owner
    /// alone.
    private func bind() throws(Failure) -> Int32 {
        try clearStaleSocket()
        let directory = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(
                atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw .system(operation: "mkdir", code: Int32((error as NSError).code))
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw .system(operation: "socket", code: errno) }
        var address = Self.address(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        // A connection made between binding and narrowing the mode is still
        // refused by the peer check.
        guard bound == 0, chmod(path, 0o600) == 0, listen(descriptor, 16) == 0,
            fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) == 0,
            fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0
        else {
            let code = errno
            Darwin.close(descriptor)
            throw .system(operation: "bind", code: code)
        }
        return descriptor
    }

    /// Removes a socket nothing answers at `path`, which a Crest that quit
    /// unexpectedly left behind.
    private func clearStaleSocket() throws(Failure) {
        var status = stat()
        guard lstat(path, &status) == 0 else { return }
        guard status.st_mode & S_IFMT == S_IFSOCK else { throw .occupied }
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { throw .system(operation: "socket", code: errno) }
        defer { Darwin.close(probe) }
        var address = Self.address(path)
        let answered = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard answered != 0 else { throw .inUse }
        unlink(path)
    }

    /// The address of a socket at `path`, which must fit one.
    private static func address(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            let utf8 = Array(path.utf8.prefix(bytes.count - 1))
            bytes.copyBytes(from: utf8)
        }
        return address
    }

    /// The file at `path` by its device and inode, or nil when there is none.
    private static func identity(of path: String) -> FileIdentity? {
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }
        return FileIdentity(device: status.st_dev, inode: status.st_ino)
    }
}
