import Foundation
import Observation

@MainActor
protocol BrowserPagePermissionProviding: AnyObject {
    var sitePermissionRequests: BrowserPagePermissionController { get }
}

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

    func response(
        to permission: BrowserSitePermission,
        origin: BrowserSiteOrigin,
        topLevelOrigin: BrowserSiteOrigin,
        spaceName: String
    ) async -> BrowserSitePermissionPromptResponse {
        await withCheckedContinuation { continuation in
            request(permission, origin: origin, topLevelOrigin: topLevelOrigin, spaceName: spaceName) { response in
                let result: BrowserSitePermissionPromptResponse
                switch response {
                case .allowOnce: result = .allowOnce
                case .grantPersistently: result = .grantPersistently
                case .denyPersistently: result = .denyPersistently
                case .denyOnce, nil: result = .denyOnce
                }
                continuation.resume(returning: result)
            }
        }
    }

    func authorize(
        _ permission: BrowserSitePermission,
        origin: BrowserSiteOrigin,
        topLevelOrigin: BrowserSiteOrigin,
        spaceID: SpaceID,
        spaceName: String,
        permissionCenter: BrowserSitePermissionCenter
    ) async -> Bool {
        switch permissionCenter.decision(for: permission, origin: origin, in: spaceID) {
        case .grantForSession, .grantPersistently: return true
        case .denyForSession, .denyPersistently: return false
        case .ask: break
        }
        let generation = generation
        let response = await response(
            to: permission, origin: origin, topLevelOrigin: topLevelOrigin, spaceName: spaceName)
        guard generation == self.generation else { return false }
        let latest = permissionCenter.decision(for: permission, origin: origin, in: spaceID)
        guard latest != .denyPersistently, latest != .denyForSession else { return false }
        switch response {
        case .allowOnce: return true
        case .denyOnce: return false
        case .grantPersistently, .denyPersistently:
            permissionCenter.setDecision(
                response == .grantPersistently ? .grantPersistently : .denyPersistently,
                for: permission, origin: origin, in: spaceID)
            return response == .grantPersistently
        }
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
