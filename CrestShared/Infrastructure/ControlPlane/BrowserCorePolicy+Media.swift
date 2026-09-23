import Foundation

/// The store's instructions for one page media-session report.
struct BrowserMediaSessionEventDecision: Equatable, Sendable {
    /// Raw values are the core's `media.session_event` spellings.
    enum Disposition: String, Decodable, Sendable {
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
    // MARK: - Types

    private struct SessionEventRequest: Encodable {
        struct Event: Encodable {
            let sequence: UInt64
            let invalidated: Bool
            let active: Bool
            let playbackState: BrowserMediaSessionPlaybackState
        }

        struct Identity: Encodable {
            let retired: Bool
            @BrowserCoreNullable var lastSequence: UInt64?
            @BrowserCoreNullable var ordinal: UInt64?
            let dismissed: Bool
            @BrowserCoreNullable var previousPlaybackState: BrowserMediaSessionPlaybackState?
        }

        let event: Event
        let identity: Identity
        let retainedIdentities: Int
        let nextOrdinal: UInt64
    }

    private struct SessionEventAnswer: Decodable {
        @BrowserCoreOptional var accepted: Bool?
        let evictOldest: Int
        let disposition: BrowserMediaSessionEventDecision.Disposition
        let nextOrdinal: UInt64
        @BrowserCoreOptional var supersedesTabSiblings: Bool?
        @BrowserCoreOptional var ordinal: UInt64?
        @BrowserCoreOptional var clearsDismissal: Bool?
    }

    private struct ArbitrationRequest: Encodable {
        struct Session: Encodable {
            let id: String
            let ordinal: UInt64
            let playbackState: BrowserMediaSessionPlaybackState
            let audible: Bool
        }

        let sessions: [Session]
    }

    private struct ArbitrationAnswer: Decodable {
        let order: [Int]
        @BrowserCoreOptional var nowPlaying: Int?
    }

    // MARK: - Actions - Media

    /// Nil when the report is stale, from a retired document, or the core
    /// cannot answer; the store then keeps its state exactly as it is.
    static func mediaSessionEvent(
        _ event: BrowserMediaSessionPageEvent, isRetired: Bool, lastSequence: UInt64?,
        ordinal: UInt64?, isDismissed: Bool, previousPlayback: BrowserMediaSessionPlaybackState?,
        retainedIdentities: Int, nextOrdinal: UInt64
    ) -> BrowserMediaSessionEventDecision? {
        let request = SessionEventRequest(
            event: SessionEventRequest.Event(
                sequence: event.sequence, invalidated: event.isInvalidated, active: event.hasActiveSession,
                playbackState: event.playbackState),
            identity: SessionEventRequest.Identity(
                retired: isRetired, lastSequence: lastSequence, ordinal: ordinal, dismissed: isDismissed,
                previousPlaybackState: previousPlayback),
            retainedIdentities: retainedIdentities, nextOrdinal: nextOrdinal)
        guard let answer = evaluate(.mediaSessionEvent, request, answer: SessionEventAnswer.self),
            answer.accepted == true, answer.evictOldest >= 0
        else { return nil }
        return BrowserMediaSessionEventDecision(
            evictOldest: answer.evictOldest, disposition: answer.disposition,
            supersedesTabSiblings: answer.supersedesTabSiblings == true,
            ordinal: answer.ordinal, nextOrdinal: answer.nextOrdinal,
            clearsDismissal: answer.clearsDismissal == true)
    }

    /// The display order of `sessions` and the one that owns the system's Now
    /// Playing. Nil when the core cannot answer.
    static func mediaSessionArbitration(_ sessions: [BrowserMediaSessionSnapshot])
        -> (order: [BrowserMediaSessionSnapshot], nowPlaying: BrowserMediaSessionSnapshot?)?
    {
        let request = ArbitrationRequest(
            sessions: sessions.map { session in
                ArbitrationRequest.Session(
                    id: session.id.id, ordinal: session.orderingOrdinal, playbackState: session.playbackState,
                    audible: session.isAudible)
            })
        guard let answer = evaluate(.mediaArbitrate, request, answer: ArbitrationAnswer.self),
            answer.order.count == sessions.count, Set(answer.order).count == answer.order.count,
            answer.order.allSatisfy(sessions.indices.contains)
        else { return nil }
        let owner = answer.nowPlaying.flatMap { sessions.indices.contains($0) ? sessions[$0] : nil }
        return (answer.order.map { sessions[$0] }, owner)
    }
}
