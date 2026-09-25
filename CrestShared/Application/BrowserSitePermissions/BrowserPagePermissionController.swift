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
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let permission: SitePermission
        let origin: SiteOrigin
        let topLevelOrigin: SiteOrigin
        let spaceName: String
    }

    private(set) var current: Request?
    private(set) var generation = UUID()
    @ObservationIgnored private var isPresentationAvailable = false
    @ObservationIgnored private var requests: [Request] = []
    @ObservationIgnored private var completions: [UUID: [(BrowserSitePermissionPromptResponse?) -> Void]] = [:]

    func setPresentationAvailable(_ available: Bool) {
        isPresentationAvailable = available
        if !available { cancelAll() }
    }

    func request(
        _ permission: SitePermission,
        origin: SiteOrigin,
        topLevelOrigin: SiteOrigin,
        spaceName: String,
        completion: @escaping (BrowserSitePermissionPromptResponse?) -> Void
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

    func resolve(_ id: UUID, response: BrowserSitePermissionPromptResponse) {
        guard current?.id == id else { return }
        requests.removeFirst()
        let callbacks = completions.removeValue(forKey: id) ?? []
        current = requests.first
        for callback in callbacks { callback(response) }
    }

    func response(
        to permission: SitePermission,
        origin: SiteOrigin,
        topLevelOrigin: SiteOrigin,
        spaceName: String
    ) async -> BrowserSitePermissionPromptResponse {
        await withCheckedContinuation { continuation in
            request(permission, origin: origin, topLevelOrigin: topLevelOrigin, spaceName: spaceName) { response in
                continuation.resume(returning: response ?? .denyOnce)
            }
        }
    }

    func authorize(
        _ permission: SitePermission,
        origin: SiteOrigin,
        topLevelOrigin: SiteOrigin,
        spaceID: SpaceID,
        spaceName: String,
        permissionCenter: BrowserSitePermissionCenter
    ) async -> Bool {
        let decision = permissionCenter.decision(for: permission, origin: origin, in: spaceID)
        guard decision.verdict == .ask else { return decision.grants }
        let generation = generation
        let response = await response(
            to: permission, origin: origin, topLevelOrigin: topLevelOrigin, spaceName: spaceName)
        guard generation == self.generation else { return false }
        guard !permissionCenter.decision(for: permission, origin: origin, in: spaceID).denies else { return false }
        if let savedDecision = response.savedDecision {
            permissionCenter.setDecision(savedDecision, for: permission, origin: origin, in: spaceID)
        }
        return response.grants
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
