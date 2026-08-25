import Foundation
import Observation

@MainActor
protocol BrowserMediaSessionCommandEndpoint: AnyObject {
    func performMediaSessionAction(
        _ action: BrowserMediaSessionAction,
        documentIdentifier: String
    )

    func setMediaSessionMuted(
        _ muted: Bool,
        documentIdentifier: String
    )
}

struct BrowserMediaSessionPageEvent: Equatable, Sendable {
    let documentIdentifier: String
    let sequence: UInt64
    let location: String
    let isInvalidated: Bool
    let hasActiveSession: Bool
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let playbackState: BrowserMediaSessionPlaybackState
    let isAudible: Bool
    let isMuted: Bool
    let availableActions: Set<BrowserMediaSessionAction>
}

enum BrowserMediaSessionArtworkPolicy {
    /// Preserve standards-provided artwork bytes whenever they fit the bounded
    /// native payload. Only a larger page resource is rasterized by the bridge.
    static let maximumInputBytes = 8 * 1_024 * 1_024
    static let maximumBytes = 4 * 1_024 * 1_024
    static let maximumDataURLCharacters = 5_600_128
    static let maximumSourceCharacters = 11_200_256
    static let maximumOversizePixelSize = 2_048

    /// Native rendering keeps ordinary source pixels intact. These limits are
    /// only a decode-safety boundary for unusually large compressed images.
    static let maximumWidgetPixelDimension = 4_096
    static let maximumWidgetPixelCount = 16 * 1_024 * 1_024
    static let maximumSystemPixelSize = 1_024

    static func decode(_ dataURL: String?) -> Data? {
        guard let dataURL,
            dataURL.count <= maximumDataURLCharacters,
            dataURL.hasPrefix("data:image/png;base64,")
                || dataURL.hasPrefix("data:image/jpeg;base64,")
                || dataURL.hasPrefix("data:image/webp;base64,")
        else { return nil }
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let encoded = String(dataURL[dataURL.index(after: comma)...])
        guard let data = Data(base64Encoded: encoded),
            data.count <= maximumBytes
        else { return nil }
        return data
    }
}

enum BrowserMediaSessionPageEventDecoder {
    static let maximumTextLength = 512
    static let maximumDocumentIdentifierLength = 128
    static let maximumLocationLength = 4_096

    static func decode(_ body: Any) -> BrowserMediaSessionPageEvent? {
        guard let body = body as? [String: Any],
            (body["version"] as? Int) == 1,
            let documentIdentifier = boundedString(
                body["documentIdentifier"],
                maximum: maximumDocumentIdentifierLength
            ),
            let sequenceNumber = body["sequence"] as? NSNumber,
            let location = boundedString(
                body["location"],
                maximum: maximumLocationLength
            )
        else { return nil }

        let actions = Set(
            (body["actions"] as? [String] ?? []).compactMap(
                BrowserMediaSessionAction.init(rawValue:)
            )
        )
        let playbackState =
            BrowserMediaSessionPlaybackState(
                rawValue: body["playbackState"] as? String ?? ""
            ) ?? .none
        return BrowserMediaSessionPageEvent(
            documentIdentifier: documentIdentifier,
            sequence: sequenceNumber.uint64Value,
            location: location,
            isInvalidated: body["invalidated"] as? Bool == true,
            hasActiveSession: body["active"] as? Bool == true,
            title: boundedString(body["title"], maximum: maximumTextLength),
            artist: boundedString(body["artist"], maximum: maximumTextLength),
            album: boundedString(body["album"], maximum: maximumTextLength),
            artworkData: BrowserMediaSessionArtworkPolicy.decode(
                body["artworkDataURL"] as? String
            ),
            playbackState: playbackState,
            isAudible: body["audible"] as? Bool == true,
            isMuted: body["muted"] as? Bool == true,
            availableActions: actions
        )
    }

    private static func boundedString(
        _ value: Any?,
        maximum: Int
    ) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximum else { return nil }
        return trimmed
    }
}

@Observable
@MainActor
final class BrowserMediaSessionStore: BrowserSidebarWidgetEventSource {
    private final class WeakEndpoint {
        weak var value: (any BrowserMediaSessionCommandEndpoint)?

        init(_ value: any BrowserMediaSessionCommandEndpoint) {
            self.value = value
        }
    }

    let kindID = BrowserSidebarWidgetKindID.nowPlaying
    private(set) var sessions: [BrowserMediaSessionSnapshot] = []
    var retainedEventIdentityCount: Int { lastSequenceByID.count }

    @ObservationIgnored private var snapshotsByID: [BrowserMediaSessionID: BrowserMediaSessionSnapshot] = [:]
    @ObservationIgnored private var endpointsByID: [BrowserMediaSessionID: WeakEndpoint] = [:]
    @ObservationIgnored private var ownersByID: [BrowserMediaSessionID: BrowserTabRuntimeAssignment] = [:]
    @ObservationIgnored private var lastSequenceByID: [BrowserMediaSessionID: UInt64] = [:]
    @ObservationIgnored private var sequenceOrder: [BrowserMediaSessionID] = []
    @ObservationIgnored private var retiredIDs: Set<BrowserMediaSessionID> = []
    @ObservationIgnored private var ordinalByID: [BrowserMediaSessionID: UInt64] = [:]
    @ObservationIgnored private var nextOrdinal: UInt64 = 1
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<[BrowserSidebarWidgetInstance]>.Continuation] = [:]
    @ObservationIgnored
    private var sessionSubscribers: [UUID: AsyncStream<[BrowserMediaSessionSnapshot]>.Continuation] = [:]
    /// Sessions the reader has hidden. The session itself keeps running and keeps
    /// reporting; only its card is withheld until the tab plays again.
    @ObservationIgnored private var dismissedIDs: Set<BrowserMediaSessionID> = []
    @ObservationIgnored private var publishedInstances: [BrowserSidebarWidgetInstance] = []

    /// A dismissal survives every update except a fresh start of playback, so
    /// hiding a card mid-song sticks, while pressing play on the page — or the tab
    /// starting new audio — brings it back.
    static func clearsDismissal(
        previous: BrowserMediaSessionPlaybackState?,
        next: BrowserMediaSessionPlaybackState
    ) -> Bool {
        previous != .playing && next == .playing
    }

    func receive(
        _ event: BrowserMediaSessionPageEvent,
        owner: BrowserTabRuntimeAssignment,
        fallbackTitle: String?,
        endpoint: any BrowserMediaSessionCommandEndpoint
    ) {
        let id = BrowserMediaSessionID(
            tabID: owner.tabID,
            documentIdentifier: event.documentIdentifier
        )
        guard !retiredIDs.contains(id) else { return }
        guard event.sequence > (lastSequenceByID[id] ?? 0) else { return }
        recordSequence(event.sequence, for: id)
        endpointsByID[id] = WeakEndpoint(endpoint)
        ownersByID[id] = owner
        if event.isInvalidated {
            retire(id)
            publishIfChanged()
            return
        }
        if !event.hasActiveSession {
            snapshotsByID[id] = nil
            publishIfChanged()
            return
        }

        // One document-level Media Session belongs to one tab. If a late event
        // from an older document arrives after navigation, it cannot coexist
        // with the current document under that tab identity.
        let superseded = ownersByID.keys.filter {
            $0.tabID == owner.tabID && $0 != id
        }
        for supersededID in superseded { retire(supersededID) }

        let ordinal: UInt64
        if let existing = ordinalByID[id] {
            ordinal = existing
        } else {
            ordinal = nextOrdinal
            nextOrdinal &+= 1
            ordinalByID[id] = ordinal
        }
        if dismissedIDs.contains(id),
            Self.clearsDismissal(
                previous: snapshotsByID[id]?.playbackState,
                next: event.playbackState
            )
        {
            dismissedIDs.remove(id)
        }
        snapshotsByID[id] = BrowserMediaSessionSnapshot(
            id: id,
            owner: owner,
            ownerTitle: Self.boundedFallbackTitle(fallbackTitle),
            title: event.title,
            artist: event.artist,
            album: event.album,
            artworkData: event.artworkData,
            playbackState: event.playbackState,
            isAudible: event.isAudible,
            isMuted: event.isMuted,
            availableActions: event.availableActions,
            orderingOrdinal: ordinal
        )
        publishIfChanged()
    }

    func invalidate(
        owner: BrowserTabRuntimeAssignment,
        endpoint: any BrowserMediaSessionCommandEndpoint
    ) {
        let endpointID = ObjectIdentifier(endpoint)
        let matching = ownersByID.keys.filter { id in
            guard ownersByID[id] == owner,
                let existing = endpointsByID[id]?.value
            else { return false }
            return ObjectIdentifier(existing) == endpointID
        }
        guard !matching.isEmpty else { return }
        for id in matching { retire(id) }
        publishIfChanged()
    }

    func invalidate(endpoint: any BrowserMediaSessionCommandEndpoint) {
        let endpointID = ObjectIdentifier(endpoint)
        let matching: [BrowserMediaSessionID] = endpointsByID.compactMap {
            id,
            weakEndpoint -> BrowserMediaSessionID? in
            guard let existing = weakEndpoint.value,
                ObjectIdentifier(existing) == endpointID
            else { return nil }
            return id
        }
        guard !matching.isEmpty else { return }
        for id in matching { retire(id) }
        publishIfChanged()
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
        continuation.yield(widgetInstances)
        return stream
    }

    /// The authoritative page-session stream. Platform adapters consume this
    /// rather than observing widget visibility, because hiding a card must not
    /// erase the page's actual media session.
    func sessionEvents() -> AsyncStream<[BrowserMediaSessionSnapshot]> {
        let subscriberID = UUID()
        let (stream, continuation) = AsyncStream<[BrowserMediaSessionSnapshot]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        sessionSubscribers[subscriberID] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sessionSubscribers.removeValue(forKey: subscriberID)
            }
        }
        continuation.yield(sessions)
        return stream
    }

    func perform(
        _ action: BrowserSidebarWidgetAction,
        on instanceID: BrowserSidebarWidgetID
    ) {
        guard instanceID.kindID == kindID,
            let snapshot = snapshotsByID.values.first(where: {
                $0.id.id == instanceID.instanceID
            })
        else { return }
        if action == .dismissMediaSession {
            // Hiding a card is Crest's own state, so it does not need the page to
            // still be reachable.
            guard dismissedIDs.insert(snapshot.id).inserted else { return }
            publishIfChanged()
            return
        }
        guard let endpoint = endpointsByID[snapshot.id]?.value else { return }
        if action == .toggleMute {
            guard Self.exposesMuteControl(snapshot) else { return }
            endpoint.setMediaSessionMuted(
                !snapshot.isMuted,
                documentIdentifier: snapshot.id.documentIdentifier
            )
            return
        }
        let mediaAction: BrowserMediaSessionAction?
        switch action {
        case .play:
            mediaAction = .play
        case .pause:
            mediaAction = .pause
        case .previousTrack:
            mediaAction = .previousTrack
        case .nextTrack:
            mediaAction = .nextTrack
        default:
            mediaAction = nil
        }
        guard let mediaAction,
            snapshot.availableActions.contains(mediaAction)
        else { return }
        endpoint.performMediaSessionAction(
            mediaAction,
            documentIdentifier: snapshot.id.documentIdentifier
        )
    }

    /// Muting addresses page media elements directly, so the control belongs to
    /// any session whose playback Crest has actually observed — not to the set of
    /// Media Session action handlers the page happens to register.
    private static func exposesMuteControl(
        _ snapshot: BrowserMediaSessionSnapshot
    ) -> Bool {
        snapshot.playbackState != .none
    }

    /// What the sidebar deck currently shows: every observed session except the
    /// ones the reader has hidden.
    var widgetInstances: [BrowserSidebarWidgetInstance] {
        sessions.compactMap { snapshot in
            guard !dismissedIDs.contains(snapshot.id) else { return nil }
            var actions: Set<BrowserSidebarWidgetAction> = [
                .activateOwner,
                .dismissMediaSession,
            ]
            if Self.exposesMuteControl(snapshot) {
                actions.insert(.toggleMute)
            }
            for action in snapshot.availableActions {
                switch action {
                case .play:
                    actions.insert(.play)
                case .pause:
                    actions.insert(.pause)
                case .previousTrack:
                    actions.insert(.previousTrack)
                case .nextTrack:
                    actions.insert(.nextTrack)
                }
            }
            return BrowserSidebarWidgetInstance(
                id: BrowserSidebarWidgetID(
                    kindID: kindID,
                    instanceID: snapshot.id.id
                ),
                scope: .profile(snapshot.owner.profileID),
                orderingOrdinal: snapshot.orderingOrdinal,
                presentation: .nowPlaying(snapshot),
                availableActions: actions
            )
        }
    }

    private func retire(_ id: BrowserMediaSessionID) {
        snapshotsByID[id] = nil
        endpointsByID[id] = nil
        ownersByID[id] = nil
        ordinalByID[id] = nil
        dismissedIDs.remove(id)
        retiredIDs.insert(id)
    }

    private func recordSequence(
        _ sequence: UInt64,
        for id: BrowserMediaSessionID
    ) {
        if lastSequenceByID[id] == nil { sequenceOrder.append(id) }
        lastSequenceByID[id] = sequence
        let overflow = sequenceOrder.count - 512
        guard overflow > 0 else { return }
        for expiredID in sequenceOrder.prefix(overflow) {
            lastSequenceByID[expiredID] = nil
            retiredIDs.remove(expiredID)
            if snapshotsByID[expiredID] == nil {
                endpointsByID[expiredID] = nil
                ownersByID[expiredID] = nil
                ordinalByID[expiredID] = nil
                dismissedIDs.remove(expiredID)
            }
        }
        sequenceOrder.removeFirst(overflow)
    }

    /// `sessions` stays the truth of what Crest observes; the widget stream is
    /// what a dismissal withholds. They are therefore published against separate
    /// guards, so hiding a card still reaches subscribers.
    private func publishIfChanged() {
        let next = snapshotsByID.values.sorted { lhs, rhs in
            if lhs.orderingOrdinal != rhs.orderingOrdinal {
                return lhs.orderingOrdinal < rhs.orderingOrdinal
            }
            return lhs.id.id < rhs.id.id
        }
        if next != sessions {
            sessions = next
            for continuation in sessionSubscribers.values {
                continuation.yield(next)
            }
        }
        let instances = widgetInstances
        guard instances != publishedInstances else { return }
        publishedInstances = instances
        for continuation in subscribers.values {
            continuation.yield(instances)
        }
    }

    private static func boundedFallbackTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            trimmed.count <= BrowserMediaSessionPageEventDecoder.maximumTextLength
        else { return nil }
        return trimmed
    }
}
