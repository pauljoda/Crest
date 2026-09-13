import Foundation
import Observation

/// Owns unanswered requests for one page. A detached page cannot ask through
/// another page's controls, and dismissal never creates a saved denial.
@Observable
@MainActor
final class BrowserPagePermissionController {
    enum Response: Equatable {
        case allowOnce
        case grantPersistently
        case denyOnce
        case denyPersistently
    }

    struct Request: Identifiable, Equatable {
        let id = UUID()
        let permission: BrowserSitePermission
        let origin: BrowserSiteOrigin
        let topLevelOrigin: BrowserSiteOrigin
        let spaceName: String
    }

    private(set) var current: Request?
    private(set) var generation = UUID()
    @ObservationIgnored private var isPresentationAvailable = false
    @ObservationIgnored private var requests: [Request] = []
    @ObservationIgnored private var completions: [UUID: [(Response?) -> Void]] = [:]

    func setPresentationAvailable(_ available: Bool) {
        isPresentationAvailable = available
        if !available { cancelAll() }
    }

    func request(
        _ permission: BrowserSitePermission,
        origin: BrowserSiteOrigin,
        topLevelOrigin: BrowserSiteOrigin,
        spaceName: String,
        completion: @escaping (Response?) -> Void
    ) {
        guard isPresentationAvailable else {
            completion(nil)
            return
        }
        if let existing = requests.first(where: {
            $0.permission == permission && $0.origin == origin
                && $0.topLevelOrigin == topLevelOrigin
        }) {
            completions[existing.id, default: []].append(completion)
            return
        }
        let request = Request(
            permission: permission, origin: origin,
            topLevelOrigin: topLevelOrigin, spaceName: spaceName
        )
        requests.append(request)
        completions[request.id] = [completion]
        current = requests.first
    }

    func resolve(_ id: UUID, response: Response) {
        guard current?.id == id else { return }
        requests.removeFirst()
        let callbacks = completions.removeValue(forKey: id) ?? []
        current = requests.first
        for callback in callbacks { callback(response) }
    }

    func cancelAll() {
        generation = UUID()
        let callbacks = requests.flatMap { completions[$0.id] ?? [] }
        requests.removeAll()
        completions.removeAll()
        current = nil
        for callback in callbacks { callback(nil) }
    }
}
