import Foundation
import Observation

struct CoreSnapshot: Decodable {
    let revision: String
    let workspaceId: String
    let spaces: [CoreSpace]
    let windows: [CoreWindow]
    var workspaceMode: String? = nil
    var workspaceClosing: Bool? = nil
}
struct CoreSpace: Decodable, Identifiable {
    let id: String
    let profileId: String
    let name: String
    let tabs: [CoreTab]
    let folders: [CoreFolder]
    let retention: CoreRetention?
    let requiresAuthentication: Bool?
    let isLocked: Bool?
    var isDeleting: Bool? = nil
    var deletionFailure: String? = nil
    var contentBlockingPolicy: String? = nil
    var contentBlockingPending: Bool? = nil
    var contentBlockingFailure: String? = nil
    let searchProviderId: String?
    let searchSuggestionsEnabled: Bool?
    let searchProviders: [CoreSearchProvider]?
}
struct CoreRetention: Decodable {
    let currentTabs: String
    let history: String
    let archive: String
    let downloads: String
}
struct CoreSearchProvider: Decodable, Identifiable {
    let id: String
    let name: String
}
struct CoreFolder: Decodable, Identifiable {
    let id: String
    let name: String
}
struct CoreWindow: Decodable, Identifiable {
    let id: String
    let spaceId: String
    let tabId: String?
}
@Observable
final class CoreTab: Decodable, Identifiable {
    let id: String
    private(set) var kind: String
    private(set) var url: String?
    private(set) var title: String
    private(set) var phase: String
    private(set) var placement: String
    private(set) var folderId: String?
    private(set) var splitGroupId: String?
    private(set) var isLoading: Bool
    private(set) var canGoBack: Bool
    private(set) var canGoForward: Bool
    private(set) var failure: String?
    private(set) var keepsPageLoaded: Bool

    private enum CodingKeys: String, CodingKey {
        case id, kind, url, title, phase, placement, folderId, splitGroupId, isLoading, canGoBack, canGoForward, failure, keepsPageLoaded
    }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        kind = try fields.decode(String.self, forKey: .kind)
        url = try fields.decodeIfPresent(String.self, forKey: .url)
        title = try fields.decode(String.self, forKey: .title)
        phase = try fields.decode(String.self, forKey: .phase)
        placement = try fields.decode(String.self, forKey: .placement)
        folderId = try fields.decodeIfPresent(String.self, forKey: .folderId)
        splitGroupId = try fields.decodeIfPresent(String.self, forKey: .splitGroupId)
        isLoading = try fields.decode(Bool.self, forKey: .isLoading)
        canGoBack = try fields.decode(Bool.self, forKey: .canGoBack)
        canGoForward = try fields.decode(Bool.self, forKey: .canGoForward)
        failure = try fields.decodeIfPresent(String.self, forKey: .failure)
        keepsPageLoaded = try fields.decodeIfPresent(Bool.self, forKey: .keepsPageLoaded) ?? false
    }
    func apply(_ updated: CoreTab) {
        precondition(id == updated.id)
        kind = updated.kind; url = updated.url; title = updated.title; phase = updated.phase
        placement = updated.placement; folderId = updated.folderId; isLoading = updated.isLoading
        splitGroupId = updated.splitGroupId
        canGoBack = updated.canGoBack; canGoForward = updated.canGoForward; failure = updated.failure
        keepsPageLoaded = updated.keepsPageLoaded
    }
}

enum CoreAdapterDescriptor {
    #if os(macOS)
        static let platform = "macos"
        static let nativeUI = "appkit"
    #else
        static let platform = "ios"
        static let nativeUI = "uikit"
    #endif
    static func make(
        id: String, role: String, implementation: String, supported: [String],
        unverified: [String] = [], unavailable: [String] = [], limitations: [String] = []
    ) throws -> Data {
        var capabilities: [String: Any] = [:]
        for capability in supported + unverified + unavailable {
            capabilities[capability] = [
                "status": supported.contains(capability) ? "supported" : unavailable.contains(capability) ? "unavailable" : "unverified",
                "contractVersion": 1,
                "scope": "\(platform) \(ProcessInfo.processInfo.operatingSystemVersionString); ephemeral profiles",
                "limitations": limitations,
                "evidence": "Experimental adapter contract; promotion requires live parity validation",
            ]
        }
        return try JSONSerialization.data(withJSONObject: [
            "adapterId": id, "role": role, "implementationId": implementation,
            "implementationVersion": "1", "protocolVersion": 1, "capabilities": capabilities,
        ])
    }
}

struct CoreRecordsPage: Decodable {
    let workspaceId: String
    let spaceId: String
    let windowId: String
    let queryId: String
    let kind: String
    let offset: Int
    let total: Int
    let items: [CoreRecord]
}
struct CoreRecord: Decodable, Identifiable {
    let id: String
    let title: String
    let url: String?
    let date: Double
    let visitCount: Int
}
