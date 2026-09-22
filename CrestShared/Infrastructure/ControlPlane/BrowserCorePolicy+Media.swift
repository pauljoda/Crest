import Foundation

/// The store's instructions for one page media-session report.
struct BrowserMediaSessionEventDecision: Equatable, Sendable {
    enum Disposition: String, Sendable {
        /// Forget the document for good; late reports from it are ignored.
        case retire
        /// Withdraw the card but keep the document's identity and ordinal.
        case clear
        /// Publish the session, superseding every other document of its tab.
        case publish
    }

    let evictOldest: Int
    let disposition: Disposition
    let supersedesTabSiblings: Bool
    let ordinal: UInt64?
    let nextOrdinal: UInt64
    let clearsDismissal: Bool
}

/// Media-session arbitration owned by the portable core, identical for the
/// WebKit bridge and Chromium's native session. Only ordering and lifecycle
/// facts cross; metadata, artwork and command endpoints stay in the store.
extension BrowserCorePolicy {
    /// Nil when the report is stale, from a retired document, or the core
    /// cannot answer; the store then keeps its state exactly as it is.
    static func mediaSessionEvent(_ event: BrowserMediaSessionPageEvent, isRetired: Bool, lastSequence: UInt64?,
        ordinal: UInt64?, isDismissed: Bool, previousPlayback: BrowserMediaSessionPlaybackState?,
        retainedIdentities: Int, nextOrdinal: UInt64) -> BrowserMediaSessionEventDecision? {
        guard let response = evaluate([
            "version": 1, "operation": "media.session_event",
            "event": [
                "sequence": NSNumber(value: event.sequence), "invalidated": event.isInvalidated,
                "active": event.hasActiveSession, "playbackState": event.playbackState.rawValue,
            ],
            "identity": [
                "retired": isRetired, "lastSequence": lastSequence.map { NSNumber(value: $0) } as Any? ?? NSNull(),
                "ordinal": ordinal.map { NSNumber(value: $0) } as Any? ?? NSNull(), "dismissed": isDismissed,
                "previousPlaybackState": previousPlayback?.rawValue as Any? ?? NSNull(),
            ],
            "retainedIdentities": retainedIdentities, "nextOrdinal": NSNumber(value: nextOrdinal),
        ]), response["accepted"] as? Bool == true,
            let evict = response["evictOldest"] as? Int, evict >= 0,
            let disposition = (response["disposition"] as? String).flatMap(BrowserMediaSessionEventDecision.Disposition.init),
            let next = (response["nextOrdinal"] as? NSNumber)?.uint64Value
        else { return nil }
        return BrowserMediaSessionEventDecision(
            evictOldest: evict, disposition: disposition,
            supersedesTabSiblings: response["supersedesTabSiblings"] as? Bool == true,
            ordinal: (response["ordinal"] as? NSNumber)?.uint64Value, nextOrdinal: next,
            clearsDismissal: response["clearsDismissal"] as? Bool == true)
    }

    /// The display order of `sessions` and the one that owns the system's Now
    /// Playing. Nil when the core cannot answer.
    static func mediaSessionArbitration(_ sessions: [BrowserMediaSessionSnapshot])
        -> (order: [BrowserMediaSessionSnapshot], nowPlaying: BrowserMediaSessionSnapshot?)? {
        guard let response = evaluate([
            "version": 1, "operation": "media.arbitrate",
            "sessions": sessions.map { session in
                [
                    "id": session.id.id, "ordinal": NSNumber(value: session.orderingOrdinal),
                    "playbackState": session.playbackState.rawValue, "audible": session.isAudible,
                ] as [String: Any]
            },
        ]), let order = response["order"] as? [Int], order.count == sessions.count,
            Set(order).count == order.count, order.allSatisfy(sessions.indices.contains)
        else { return nil }
        let owner = (response["nowPlaying"] as? Int).flatMap { sessions.indices.contains($0) ? sessions[$0] : nil }
        return (order.map { sessions[$0] }, owner)
    }
}
