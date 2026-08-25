import Foundation
import Observation

@MainActor
protocol BrowserSidebarWidgetEventSource: AnyObject {
    var kindID: BrowserSidebarWidgetKindID { get }

    /// A source retains authoritative state independently of this stream. Every
    /// subscription first yields that state, then keeps only the newest pending
    /// update so a suspended sidebar cannot accumulate an unbounded queue.
    func events() -> AsyncStream<[BrowserSidebarWidgetInstance]>

    func perform(
        _ action: BrowserSidebarWidgetAction,
        on instanceID: BrowserSidebarWidgetID
    )
}

struct BrowserSidebarWidgetHostRegistration: Equatable, Sendable {
    let platform: BrowserSidebarWidgetPlatform
    let capabilities: BrowserSidebarWidgetCapabilities
    let isActive: Bool
}

@Observable
@MainActor
final class BrowserSidebarWidgetRuntime {
    let registry: BrowserSidebarWidgetRegistry

    private(set) var publishedInstances: [BrowserSidebarWidgetInstance] = []
    private(set) var visibilityRevision = 0
    /// One deck, one centred card, shared by every Space of every profile.
    private(set) var carouselSelection: BrowserSidebarWidgetID?

    @ObservationIgnored private let sourcesByKindID: [BrowserSidebarWidgetKindID: any BrowserSidebarWidgetEventSource]
    @ObservationIgnored private var hosts: [BrowserWindowID: BrowserSidebarWidgetHostRegistration] = [:]
    @ObservationIgnored private var workerTasks: [BrowserSidebarWidgetKindID: Task<Void, Never>] = [:]
    @ObservationIgnored private var instancesByKindID: [BrowserSidebarWidgetKindID: [BrowserSidebarWidgetInstance]] =
        [:]
    @ObservationIgnored private var insertionOrdinalByInstanceID: [BrowserSidebarWidgetID: UInt64] = [:]
    @ObservationIgnored private var lastAutomaticInsertionOrdinal: UInt64 = 0
    @ObservationIgnored private var nextInsertionOrdinal: UInt64 = 0

    init(
        registrations: [BrowserSidebarWidgetRegistration],
        sources: [any BrowserSidebarWidgetEventSource]
    ) {
        registry = BrowserSidebarWidgetRegistry(registrations: registrations)
        var uniqueSources: [BrowserSidebarWidgetKindID: any BrowserSidebarWidgetEventSource] = [:]
        for source in sources {
            precondition(
                uniqueSources[source.kindID] == nil,
                "A sidebar widget kind may own only one background source."
            )
            precondition(
                registry.registration(for: source.kindID) != nil,
                "Every sidebar widget source must have a registration."
            )
            uniqueSources[source.kindID] = source
        }
        sourcesByKindID = uniqueSources
    }

    deinit {
        for task in workerTasks.values { task.cancel() }
    }

    func activateHost(
        id: BrowserWindowID,
        platform: BrowserSidebarWidgetPlatform = .current,
        capabilities: BrowserSidebarWidgetCapabilities
    ) {
        let next = BrowserSidebarWidgetHostRegistration(
            platform: platform,
            capabilities: capabilities,
            isActive: true
        )
        guard hosts[id] != next else { return }
        hosts[id] = next
        reconcileWorkers()
    }

    func suspendHost(id: BrowserWindowID) {
        guard let current = hosts[id], current.isActive else { return }
        hosts[id] = BrowserSidebarWidgetHostRegistration(
            platform: current.platform,
            capabilities: current.capabilities,
            isActive: false
        )
        reconcileWorkers()
    }

    func removeHost(id: BrowserWindowID) {
        guard hosts.removeValue(forKey: id) != nil else { return }
        reconcileWorkers()
    }

    func instances(
        platform: BrowserSidebarWidgetPlatform = .current,
        capabilities: BrowserSidebarWidgetCapabilities
    ) -> [BrowserSidebarWidgetInstance] {
        registry.visibleInstances(
            from: publishedInstances,
            platform: platform,
            capabilities: capabilities
        )
    }

    func perform(
        _ action: BrowserSidebarWidgetAction,
        on instanceID: BrowserSidebarWidgetID
    ) {
        sourcesByKindID[instanceID.kindID]?.perform(
            action,
            on: instanceID
        )
    }

    func reconcileCarouselSelection(
        visibleInstances: [BrowserSidebarWidgetInstance]
    ) {
        guard !visibleInstances.isEmpty else {
            setCarouselSelection(nil)
            return
        }

        let latestID = BrowserSidebarWidgetCarouselPolicy.mostRecentlyInsertedID(
            in: visibleInstances,
            insertionOrdinals: insertionOrdinalByInstanceID
        )
        let latestOrdinal = latestID.flatMap { insertionOrdinalByInstanceID[$0] } ?? 0
        let currentIsVisible = visibleInstances.contains {
            $0.id == carouselSelection
        }

        if latestOrdinal > lastAutomaticInsertionOrdinal {
            lastAutomaticInsertionOrdinal = latestOrdinal
            setCarouselSelection(latestID)
        } else if !currentIsVisible {
            setCarouselSelection(latestID ?? visibleInstances.first?.id)
        }
    }

    func selectCarouselInstance(
        _ instanceID: BrowserSidebarWidgetID,
        visibleInstances: [BrowserSidebarWidgetInstance]
    ) {
        guard visibleInstances.contains(where: { $0.id == instanceID }) else {
            return
        }
        setCarouselSelection(instanceID)
    }

    func isWorkerRunning(for kindID: BrowserSidebarWidgetKindID) -> Bool {
        workerTasks[kindID] != nil
    }

    private func reconcileWorkers() {
        for registration in registry.registrations {
            guard let source = sourcesByKindID[registration.id] else {
                continue
            }
            let shouldRun = hosts.values.contains { host in
                host.isActive
                    && registry.supports(
                        registration,
                        platform: host.platform,
                        capabilities: host.capabilities
                    )
            }
            if shouldRun, workerTasks[registration.id] == nil {
                startWorker(for: registration.id, source: source)
            } else if !shouldRun,
                let task = workerTasks.removeValue(forKey: registration.id)
            {
                task.cancel()
            }
        }
    }

    private func startWorker(
        for kindID: BrowserSidebarWidgetKindID,
        source: any BrowserSidebarWidgetEventSource
    ) {
        let stream = source.events()
        workerTasks[kindID] = Task { @MainActor [weak self] in
            for await instances in stream {
                guard !Task.isCancelled else { return }
                self?.replaceInstances(for: kindID, with: instances)
            }
        }
    }

    private func replaceInstances(
        for kindID: BrowserSidebarWidgetKindID,
        with candidates: [BrowserSidebarWidgetInstance]
    ) {
        guard let registration = registry.registration(for: kindID) else {
            return
        }
        let matching = candidates.filter { $0.id.kindID == kindID }
        let normalized: [BrowserSidebarWidgetInstance]
        switch registration.instancePolicy {
        case .single:
            normalized = matching.sorted { $0.id.id < $1.id.id }.prefix(1).map { $0 }
        case .multiple:
            var unique: [BrowserSidebarWidgetID: BrowserSidebarWidgetInstance] = [:]
            for instance in matching { unique[instance.id] = instance }
            normalized = unique.values.sorted { $0.id.id < $1.id.id }
        }
        guard instancesByKindID[kindID] != normalized else { return }
        instancesByKindID[kindID] = normalized
        let next = registry.registrations.flatMap {
            instancesByKindID[$0.id] ?? []
        }
        guard next != publishedInstances else { return }
        let previousIDs = Set(publishedInstances.map(\.id))
        let nextIDs = Set(next.map(\.id))
        let addedInstances =
            next
            .filter { !previousIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.orderingOrdinal != rhs.orderingOrdinal {
                    return lhs.orderingOrdinal < rhs.orderingOrdinal
                }
                return lhs.id.id < rhs.id.id
            }
        for instance in addedInstances {
            nextInsertionOrdinal &+= 1
            insertionOrdinalByInstanceID[instance.id] = nextInsertionOrdinal
        }
        insertionOrdinalByInstanceID = insertionOrdinalByInstanceID.filter {
            nextIDs.contains($0.key)
        }
        if let carouselSelection, !nextIDs.contains(carouselSelection) {
            self.carouselSelection = nil
        }
        publishedInstances = next
        visibilityRevision &+= 1
    }

    private func setCarouselSelection(
        _ instanceID: BrowserSidebarWidgetID?
    ) {
        guard carouselSelection != instanceID else { return }
        carouselSelection = instanceID
    }
}
