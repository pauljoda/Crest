import Foundation

struct BrowserSidebarWidgetKindID: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    static let nowPlaying = Self(rawValue: "crest.now-playing")
    static let softwareUpdate = Self(rawValue: "crest.software-update")
}

struct BrowserSidebarWidgetID: Hashable, Identifiable, Sendable {
    let kindID: BrowserSidebarWidgetKindID
    let instanceID: String

    var id: String { "\(kindID.rawValue):\(instanceID)" }
}

struct BrowserSidebarWidgetPlatform: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let macOS = Self(rawValue: 1 << 0)
    static let mobile = Self(rawValue: 1 << 1)
    static let all: Self = [.macOS, .mobile]

    #if os(macOS)
        static let current = Self.macOS
    #else
        static let current = Self.mobile
    #endif
}

struct BrowserSidebarWidgetCapabilities: OptionSet, Hashable, Sendable {
    let rawValue: Int

    /// The shell has a sidebar that remains beside web content.
    static let persistentSidebar = Self(rawValue: 1 << 0)
    /// Standard page Media Session state can be observed and controlled.
    static let mediaSessions = Self(rawValue: 1 << 1)
    /// This build is distributed directly and owns a Sparkle updater.
    static let directSoftwareUpdates = Self(rawValue: 1 << 2)
}

enum BrowserSidebarWidgetInstancePolicy: Equatable, Sendable {
    case single
    case multiple
}

struct BrowserSidebarWidgetRegistration: Equatable, Identifiable, Sendable {
    let id: BrowserSidebarWidgetKindID
    let order: Int
    let platforms: BrowserSidebarWidgetPlatform
    let requiredCapabilities: BrowserSidebarWidgetCapabilities
    let instancePolicy: BrowserSidebarWidgetInstancePolicy
    let backgroundActivityID: String?
}

extension BrowserSidebarWidgetRegistration {
    static let nowPlaying = Self(
        id: .nowPlaying,
        order: 200,
        platforms: .all,
        requiredCapabilities: [.mediaSessions],
        instancePolicy: .multiple,
        backgroundActivityID: "crest.media-session-observation"
    )

    static let softwareUpdate = Self(
        id: .softwareUpdate,
        order: 100,
        platforms: .macOS,
        requiredCapabilities: [.directSoftwareUpdates],
        instancePolicy: .single,
        backgroundActivityID: "crest.software-update-observation"
    )
}

/// Who authored a widget. Sources still tag what they publish, but the deck is a
/// single global layer: visibility never consults the scope, so a tab playing
/// media in one profile stays on the card stack in every Space of every profile.
enum BrowserSidebarWidgetScope: Equatable, Sendable {
    case application
    case profile(UUID)
}

enum BrowserSidebarWidgetHostPolicy {
    static func shouldRender(
        sidebarIsPresented: Bool,
        isPrivateBrowsing: Bool
    ) -> Bool {
        sidebarIsPresented && !isPrivateBrowsing
    }
}

enum BrowserSidebarWidgetCarouselPolicy {
    static func mostRecentlyInsertedID(
        in instances: [BrowserSidebarWidgetInstance],
        insertionOrdinals: [BrowserSidebarWidgetID: UInt64]
    ) -> BrowserSidebarWidgetID? {
        instances.max { lhs, rhs in
            let lhsOrdinal = insertionOrdinals[lhs.id] ?? 0
            let rhsOrdinal = insertionOrdinals[rhs.id] ?? 0
            if lhsOrdinal != rhsOrdinal {
                return lhsOrdinal < rhsOrdinal
            }
            return lhs.id.id < rhs.id.id
        }?.id
    }

    /// Clamping adjacency for surfaces that represent a bounded run of cards.
    static func adjacentID(
        to selectedID: BrowserSidebarWidgetID?,
        in instances: [BrowserSidebarWidgetInstance],
        direction: BrowserSidebarWidgetCarouselDirection
    ) -> BrowserSidebarWidgetID? {
        guard !instances.isEmpty else { return nil }
        guard
            let selectedID,
            let selectedIndex = instances.firstIndex(where: { $0.id == selectedID })
        else {
            return instances.first?.id
        }

        switch direction {
        case .previous:
            return instances[max(instances.startIndex, selectedIndex - 1)].id
        case .next:
            return instances[min(instances.index(before: instances.endIndex), selectedIndex + 1)].id
        }
    }

    /// Wrapping adjacency: the deck is a loop the reader flips through, so the
    /// last card hands back to the first rather than dead-ending.
    static func cyclicAdjacentID(
        to selectedID: BrowserSidebarWidgetID?,
        in instances: [BrowserSidebarWidgetInstance],
        direction: BrowserSidebarWidgetCarouselDirection
    ) -> BrowserSidebarWidgetID? {
        guard !instances.isEmpty else { return nil }
        guard
            let selectedID,
            let selectedIndex = instances.firstIndex(where: { $0.id == selectedID })
        else {
            return instances.first?.id
        }
        let count = instances.count
        let step = direction == .next ? 1 : count - 1
        return instances[(selectedIndex + step) % count].id
    }

    /// The cards a vertical deck shows: the selected card first, then the cards
    /// it will flip to, wrapping until the visible depth is filled.
    static func deckOrder(
        from selectedID: BrowserSidebarWidgetID?,
        in instances: [BrowserSidebarWidgetInstance],
        visibleDepth: Int
    ) -> [BrowserSidebarWidgetInstance] {
        guard !instances.isEmpty, visibleDepth > 0 else { return [] }
        let start =
            selectedID
            .flatMap { id in instances.firstIndex(where: { $0.id == id }) }
            ?? instances.startIndex
        let count = min(visibleDepth, instances.count)
        return (0..<count).map { offset in
            instances[(start + offset) % instances.count]
        }
    }
}

enum BrowserSidebarWidgetCarouselDirection: Equatable, Sendable {
    case previous
    case next
}

enum BrowserSidebarWidgetCarouselLayoutPolicy {
    static func cardInsets(
        instanceCount _: Int
    ) -> BrowserSidebarWidgetCarouselCardInsets {
        .zero
    }

    static func shouldUpdateActiveCardHeight(
        currentHeight: CGFloat?,
        measuredHeight: CGFloat,
        isSelected: Bool
    ) -> Bool {
        guard isSelected, measuredHeight > 0 else { return false }
        guard let currentHeight else { return true }
        return abs(currentHeight - measuredHeight) > 0.5
    }
}

enum BrowserSidebarWidgetDeckGestureAxis: Equatable, Sendable {
    case horizontal
    case vertical
}

enum BrowserSidebarWidgetDeckGesturePolicy {
    static var currentPlatformAxis: BrowserSidebarWidgetDeckGestureAxis {
        #if os(iOS)
            .vertical
        #else
            .horizontal
        #endif
    }

    static func primaryTranslation(
        horizontal: CGFloat,
        vertical: CGFloat,
        axis: BrowserSidebarWidgetDeckGestureAxis
    ) -> CGFloat {
        switch axis {
        case .horizontal: horizontal
        case .vertical: vertical
        }
    }

    static func cardOffset(
        trackedTranslation: CGFloat,
        slotOffset: CGFloat,
        axis: BrowserSidebarWidgetDeckGestureAxis
    ) -> CGSize {
        switch axis {
        case .horizontal:
            CGSize(width: trackedTranslation, height: slotOffset)
        case .vertical:
            CGSize(width: 0, height: slotOffset + trackedTranslation)
        }
    }
}

struct BrowserSidebarWidgetCarouselCardInsets: Equatable, Sendable {
    let leading: CGFloat
    let trailing: CGFloat

    static let zero = Self(leading: 0, trailing: 0)
}

enum BrowserMediaSessionPlaybackState: String, Equatable, Sendable {
    case none
    case paused
    case playing
}

enum BrowserMediaSessionAction: String, CaseIterable, Hashable, Sendable {
    case play
    case pause
    case previousTrack = "previoustrack"
    case nextTrack = "nexttrack"
}

struct BrowserMediaSessionID: Hashable, Identifiable, Sendable {
    let tabID: TabID
    let documentIdentifier: String

    var id: String {
        "\(tabID.rawValue.uuidString.lowercased()):\(documentIdentifier)"
    }
}

struct BrowserMediaSessionSnapshot: Equatable, Identifiable, Sendable {
    let id: BrowserMediaSessionID
    let owner: BrowserTabRuntimeAssignment
    /// The owning tab's Crest-visible name, including a reader-supplied custom
    /// title. This is intentionally independent of page playback metadata.
    let ownerTitle: String?
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let playbackState: BrowserMediaSessionPlaybackState
    let isAudible: Bool
    /// Every media element the page has surfaced is muted. Distinct from
    /// `isAudible`, which also goes false for paused or zero-volume playback.
    let isMuted: Bool
    let availableActions: Set<BrowserMediaSessionAction>
    let orderingOrdinal: UInt64

    var ownerDisplayTitle: String { ownerTitle ?? "Media tab" }

    var mediaDisplayTitle: String { title ?? "Media from this tab" }

    /// System Now Playing still needs a single primary title. Prefer the
    /// standards-provided media title, with the stable tab title as its fallback.
    var displayTitle: String { title ?? ownerTitle ?? "Untitled media" }

    var secondaryMetadata: String? {
        [artist, album]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
            .nilIfEmpty
    }
}

enum BrowserSoftwareUpdateWidgetPhase: Equatable, Sendable {
    case checking
    case available
    case downloading
    case extracting
    case readyToInstall
    case installing
    case failed
    case unavailable
}

struct BrowserSoftwareUpdateWidgetSnapshot: Equatable, Sendable {
    let phase: BrowserSoftwareUpdateWidgetPhase
    let title: String
    let version: String?
    let build: String?
    let message: String?
    let progress: Double?
    let isInformationOnly: Bool
    let allowsInstallation: Bool
    let allowsSkipping: Bool
    let allowsCancellation: Bool
    let allowsInstallAndRelaunch: Bool
    let isFixture: Bool
}

enum BrowserSidebarWidgetPresentation: Equatable, Sendable {
    case nowPlaying(BrowserMediaSessionSnapshot)
    case softwareUpdate(BrowserSoftwareUpdateWidgetSnapshot)
}

enum BrowserSidebarWidgetAction: Hashable, Sendable {
    case activateOwner
    case play
    case pause
    case previousTrack
    case nextTrack
    /// Widget-level only: muting is an element property, not a Media Session
    /// action a page can register a handler for.
    case toggleMute
    /// Hides this session's card until its tab plays again. Widget-level only.
    case dismissMediaSession
    case installUpdate
    case dismissExactUpdate
    case cancelUpdate
    case installAndRelaunch
    case acknowledgeError
}

struct BrowserSidebarWidgetInstance: Equatable, Identifiable, Sendable {
    let id: BrowserSidebarWidgetID
    let scope: BrowserSidebarWidgetScope
    let orderingOrdinal: UInt64
    let presentation: BrowserSidebarWidgetPresentation
    let availableActions: Set<BrowserSidebarWidgetAction>
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
