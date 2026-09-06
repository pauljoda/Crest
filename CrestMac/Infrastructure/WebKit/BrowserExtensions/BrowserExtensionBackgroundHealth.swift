import Foundation

/// An on-demand round trip to the background, rather than WebKit's page-level
/// loaded flag. No timer runs while an extension is idle.
@MainActor
final class BrowserExtensionBackgroundHealth {
    static let shared = BrowserExtensionBackgroundHealth()
    nonisolated static let resourceName = "crest-webextension-background-health-v1"

    private struct Endpoint {
        let id: UUID
        let publish: ([String: Any]) -> Void
    }
    private struct Pending {
        let endpoint: UUID
        let finish: (Bool) -> Void
    }
    private var endpoints: [BrowserExtensionServiceClientID: Endpoint] = [:]
    private var pending: [String: Pending] = [:]

    func register(client: BrowserExtensionServiceClientID, id: UUID, publish: @escaping ([String: Any]) -> Void) {
        endpoints[client] = Endpoint(id: id, publish: publish)
    }

    func unregister(client: BrowserExtensionServiceClientID, id: UUID) {
        guard endpoints[client]?.id == id else { return }
        endpoints[client] = nil
        let requests = pending.filter { $0.value.endpoint == id }
        for (nonce, request) in requests {
            pending[nonce] = nil
            request.finish(false)
        }
    }

    func acknowledge(nonce: String, endpoint: UUID) {
        guard let request = pending[nonce], request.endpoint == endpoint else { return }
        pending[nonce] = nil
        request.finish(true)
    }

    func responds(client: BrowserExtensionServiceClientID, timeout: Duration = .seconds(3)) async -> Bool {
        guard let endpoint = endpoints[client] else { return false }
        let nonce = UUID().uuidString
        return await withCheckedContinuation { continuation in
            pending[nonce] = Pending(endpoint: endpoint.id, finish: { continuation.resume(returning: $0) })
            endpoint.publish(["api": "background.health.ping", "nonce": nonce])
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let request = self?.pending.removeValue(forKey: nonce) else { return }
                request.finish(false)
            }
        }
    }
}
