import Foundation

/// Media-session arbitration owned by the portable core, identical for the
/// WebKit bridge and Chromium's native session. Only ordering, lifecycle and
/// control facts cross, and the core alone decides which sessions take a card;
/// metadata, artwork and command endpoints stay in the store.
extension BrowserCorePolicy {
    // MARK: - Actions - Media

    /// Nil when the report is stale, from a retired document, or the core
    /// cannot answer; the store then keeps its state exactly as it is.
    static func mediaSessionEvent(
        _ event: BrowserMediaSessionPageEvent, isRetired: Bool, lastSequence: UInt64?,
        ordinal: UInt64?, isDismissed: Bool, previousPlayback: BrowserMediaSessionPlaybackState?,
        retainedIdentities: Int, nextOrdinal: UInt64
    ) -> MediaSessionEventDecision? {
        let question = MediaSessionReport(
            event: MediaSessionEvent(
                sequence: event.sequence, isInvalidated: event.isInvalidated, hasActiveSession: event.hasActiveSession,
                playback: event.playbackState.core, isMuted: event.isMuted,
                actions: Array(event.availableActions)),
            identity: MediaSessionIdentity(
                isRetired: isRetired, lastSequence: lastSequence, ordinal: ordinal, isDismissed: isDismissed,
                previousPlayback: previousPlayback?.core),
            retainedIdentities: retainedIdentities, nextOrdinal: nextOrdinal)
        guard let decision = try? CrestCore.answer(question), decision.accepted, decision.evictOldest >= 0 else {
            return nil
        }
        return decision
    }

    /// The display order of `sessions` and the one that owns the system's Now
    /// Playing. Nil when the core cannot answer.
    static func mediaSessionArbitration(_ sessions: [BrowserMediaSessionSnapshot])
        -> (order: [BrowserMediaSessionSnapshot], nowPlaying: BrowserMediaSessionSnapshot?)?
    {
        let question = MediaSessionOrder(
            sessions: sessions.map { session in
                MediaSessionEntry(
                    id: session.id.id, ordinal: session.orderingOrdinal, playback: session.playbackState.core,
                    isAudible: session.isAudible)
            })
        guard let answer = try? CrestCore.answer(question),
            answer.order.count == sessions.count, Set(answer.order).count == answer.order.count,
            answer.order.allSatisfy(sessions.indices.contains)
        else { return nil }
        let owner = answer.nowPlaying.flatMap { sessions.indices.contains($0) ? sessions[$0] : nil }
        return (answer.order.map { sessions[$0] }, owner)
    }
}
