import Foundation

@MainActor
final class BrowserSoftwareUpdateWidgetSource:
    BrowserSidebarWidgetEventSource
{
    let kindID = BrowserSidebarWidgetKindID.softwareUpdate

    private weak var model: BrowserSoftwareUpdateModel?
    private var currentInstance: BrowserSidebarWidgetInstance?
    private var subscribers: [UUID: AsyncStream<[BrowserSidebarWidgetInstance]>.Continuation] = [:]

    func bind(_ model: BrowserSoftwareUpdateModel) {
        self.model = model
        publish(model.sidebarWidgetSnapshot)
    }

    func publish(_ snapshot: BrowserSoftwareUpdateWidgetSnapshot?) {
        let next = snapshot.map(Self.instance(for:))
        guard next != currentInstance else { return }
        currentInstance = next
        let instances = next.map { [$0] } ?? []
        for continuation in subscribers.values {
            continuation.yield(instances)
        }
    }

    func events() -> AsyncStream<[BrowserSidebarWidgetInstance]> {
        let subscriberID = UUID()
        let (stream, continuation) = AsyncStream<[BrowserSidebarWidgetInstance]>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        subscribers[subscriberID] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                self?.subscribers.removeValue(forKey: subscriberID)
            }
        }
        continuation.yield(currentInstance.map { [$0] } ?? [])
        return stream
    }

    func perform(
        _ action: BrowserSidebarWidgetAction,
        on instanceID: BrowserSidebarWidgetID
    ) {
        guard instanceID == currentInstance?.id, let model else { return }
        switch action {
        case .declineAutomaticUpdateChecks:
            model.chooseAutomaticChecks(false)
        case .enableAutomaticUpdateChecks:
            model.chooseAutomaticChecks(true)
        case .installUpdate:
            model.installUpdate()
        case .dismissExactUpdate:
            // Sparkle persists `.skip` against the exact appcast build. Its own
            // app-scoped store is authoritative, and a newer build is therefore
            // offered again without Crest maintaining a competing dismissal key.
            model.skipUpdate()
        case .cancelUpdate:
            model.cancelCurrentOperation()
        case .installAndRelaunch:
            model.installAndRelaunchNow()
        case .retryUpdateInstallation:
            model.retryApplicationTermination()
        case .acknowledgeUpdateStatus:
            model.acknowledge()
        default:
            break
        }
    }

    private static func instance(
        for snapshot: BrowserSoftwareUpdateWidgetSnapshot
    ) -> BrowserSidebarWidgetInstance {
        var actions: Set<BrowserSidebarWidgetAction> = []
        switch snapshot.phase {
        case .permission:
            actions = [
                .declineAutomaticUpdateChecks,
                .enableAutomaticUpdateChecks,
            ]
        case .checking:
            if snapshot.allowsCancellation { actions.insert(.cancelUpdate) }
        case .available:
            if snapshot.allowsSkipping { actions.insert(.dismissExactUpdate) }
            if snapshot.allowsInstallation { actions.insert(.installUpdate) }
            if snapshot.isInformationOnly, snapshot.informationURL != nil {
                actions.insert(.viewUpdateInformation)
            }
        case .downloading:
            if snapshot.allowsCancellation { actions.insert(.cancelUpdate) }
        case .readyToInstall:
            if snapshot.allowsInstallAndRelaunch {
                actions.insert(.installAndRelaunch)
            }
            if snapshot.allowsSkipping { actions.insert(.dismissExactUpdate) }
        case .failed:
            actions = [.acknowledgeUpdateStatus]
        case .installing:
            if snapshot.allowsInstallationRetry {
                actions.insert(.retryUpdateInstallation)
            }
        case .upToDate, .installed:
            actions = [.acknowledgeUpdateStatus]
        case .extracting, .unavailable:
            break
        }
        return BrowserSidebarWidgetInstance(
            id: BrowserSidebarWidgetID(
                kindID: .softwareUpdate,
                instanceID: snapshot.build ?? snapshot.version ?? "available"
            ),
            scope: .application,
            orderingOrdinal: 0,
            presentation: .softwareUpdate(snapshot),
            availableActions: actions
        )
    }
}
