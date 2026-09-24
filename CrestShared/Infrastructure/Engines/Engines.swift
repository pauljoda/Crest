import Foundation
import OSLog
import Observation

/// The engine bindings the core hosts pages on, by kind. A composition
/// registers the engines it carries, one of them as the default, and new pages
/// open on the default. The core decides whether a page opens and on which
/// engine; the binding builds what the platform hosts.
@MainActor
@Observable
final class Engines {
    // MARK: - Types

    /// A page the platform asked the core to open, while the core asks its
    /// engine to create it.
    final class PageRequest {
        let page: CorePage
        /// TRANSITIONAL until the WebKit binding builds its own pages: how the
        /// page's owner builds it when WebKit hosts it.
        let makeWebKitPage: @MainActor (CorePage) -> AnyObject?
        /// What the engine's binding built for the platform to host.
        var built: AnyObject?

        init(page: CorePage, makeWebKitPage: @escaping @MainActor (CorePage) -> AnyObject?) {
            self.page = page
            self.makeWebKitPage = makeWebKitPage
        }
    }

    /// A page the core opened, with what its engine's binding built for the
    /// platform to host: the Mac page adapter, or iOS's page.
    struct OpenedPage {
        let page: CorePage
        let built: AnyObject
    }

    /// Carries the core's commands for one engine to its binding.
    final class Relay: @unchecked Sendable {
        let kind: EngineKind
        @MainActor weak var engines: Engines?

        @MainActor
        init(kind: EngineKind, engines: Engines) {
            self.kind = kind
            self.engines = engines
        }
    }

    // MARK: - Variables

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "Pages")

    /// The registered bindings, by kind.
    private(set) var bindings: [EngineKind: any EngineBinding] = [:]
    /// The core's handle for each registered engine, and its relay, which the
    /// core addresses while the engine stays registered.
    @ObservationIgnored private var registered: [EngineKind: (engine: UInt64, relay: Relay)] = [:]
    @ObservationIgnored private var requests: [UUID: PageRequest] = [:]
    @ObservationIgnored private unowned let core: CrestCore

    // MARK: - Initializers

    init(core: CrestCore) {
        self.core = core
    }

    // MARK: - Actions - Registration

    /// Registers a binding with the core, as the engine new pages open on when
    /// `isDefault`. A refusal is a composition bug.
    func register(_ binding: any EngineBinding, isDefault: Bool) {
        let kind = binding.integration.kind
        let relay = Relay(kind: kind, engines: self)
        binding.attach(to: self)
        do {
            let engine = try core.registerEngine(binding.integration.registration(isDefault: isDefault), relay: relay)
            registered[kind] = (engine, relay)
            bindings[kind] = binding
        } catch {
            preconditionFailure("The core refused the \(kind.name) engine: \(error)")
        }
    }

    // MARK: - Actions - Pages

    /// Opens a page through the core and answers it with what its engine built,
    /// or nil when a rule refused it or the engine built nothing. `webKit` builds
    /// the page when WebKit hosts it.
    func open(_ intent: OpenPage, webKit: @escaping @MainActor (CorePage) -> AnyObject?) -> OpenedPage? {
        let request = PageRequest(page: CorePage(id: intent.pageID, core: core), makeWebKitPage: webKit)
        requests[intent.pageID] = request
        defer { requests[intent.pageID] = nil }
        do {
            try core.send(intent)
        } catch {
            Self.logger.debug("The core opened no page: \(String(describing: error))")
            return nil
        }
        guard let built = request.built else {
            request.page.release(keepingState: false)
            return nil
        }
        return OpenedPage(page: request.page, built: built)
    }

    /// The page the core is asking a binding to create, while its owner waits.
    func request(_ pageID: UUID) -> PageRequest? {
        requests[pageID]
    }

    /// Reports what happened to one of `binding`'s pages.
    func report(_ event: some EngineEvent, from binding: any EngineBinding) {
        guard let engine = registered[binding.integration.kind]?.engine else { return }
        core.report(event, engine: engine)
    }

    // MARK: - Actions - Commands

    /// Hands a command the core issued to the binding it names.
    func run(_ command: EngineCommand, on kind: EngineKind) {
        bindings[kind]?.run(command)
    }
}
