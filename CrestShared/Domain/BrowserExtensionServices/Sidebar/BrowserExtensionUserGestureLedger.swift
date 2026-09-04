import Foundation

/// Uses monotonic uptime, not wall-clock time. A gesture belongs only to the
/// extension the person invoked and is never renewed by a broker request.
struct BrowserExtensionUserGestureLedger {
    private var gestures: [BrowserExtensionServiceClientID: TimeInterval] = [:]

    mutating func note(for client: BrowserExtensionServiceClientID, now: TimeInterval) {
        gestures = gestures.filter { now - $0.value <= 5 }
        gestures[client] = now
    }

    func hasRecentGesture(for client: BrowserExtensionServiceClientID, now: TimeInterval) -> Bool {
        guard let gesture = gestures[client] else { return false }
        return (0...5).contains(now - gesture)
    }

    mutating func remove(client: BrowserExtensionServiceClientID) { gestures[client] = nil }
}
