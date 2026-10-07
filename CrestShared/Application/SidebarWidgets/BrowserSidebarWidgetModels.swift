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

enum BrowserSidebarWidgetVisibilityPolicy: Equatable, Sendable {
    case mandatory
    case userControllable
}

struct BrowserSidebarWidgetRegistration: Equatable, Identifiable, Sendable {
    let id: BrowserSidebarWidgetKindID
    let settingsTitle: String
    let order: Int
    let platforms: BrowserSidebarWidgetPlatform
    let requiredCapabilities: BrowserSidebarWidgetCapabilities
    let instancePolicy: BrowserSidebarWidgetInstancePolicy
    let visibilityPolicy: BrowserSidebarWidgetVisibilityPolicy
    let backgroundActivityID: String?
}

extension BrowserSidebarWidgetRegistration {
    static let nowPlaying = Self(
        id: .nowPlaying,
        settingsTitle: String(localized: "Now Playing"),
        order: 200,
        platforms: .all,
        requiredCapabilities: [.mediaSessions],
        instancePolicy: .multiple,
        visibilityPolicy: .userControllable,
        backgroundActivityID: "crest.media-session-observation"
    )

    static let softwareUpdate = Self(
        id: .softwareUpdate,
        settingsTitle: String(localized: "Software Update"),
        order: 100,
        platforms: .macOS,
        requiredCapabilities: [.directSoftwareUpdates],
        instancePolicy: .single,
        visibilityPolicy: .mandatory,
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

enum BrowserMediaSessionPlaybackState: String, Encodable, Equatable, Sendable {
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
    let tabID: UUID
    let documentIdentifier: String

    var id: String {
        "\(tabID.uuidString.lowercased()):\(documentIdentifier)"
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

/// Where a software update stands, from asking to check through to the
/// installed build, with how the update window and the sidebar card say so.
struct BrowserSoftwareUpdatePhase: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// Each phase offers its own actions, so the places that build a phase's
    /// actions switch over the kind.
    enum Kinds: Sendable {
        case idle
        case permission
        case checking
        case available
        case downloading
        case extracting
        case readyToInstall
        case installing
        case upToDate
        case failed
        case installed
        case unavailable
    }

    /// The color a phase's symbol takes, which the view that draws it names.
    enum Tones: Sendable {
        case accent
        case success
        case warning
    }

    // MARK: - Static Variables

    private static let waitingSymbol = "arrow.trianglehead.2.clockwise.rotate.90"
    private static let installSymbol = "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
    private static let settledSymbol = "checkmark.circle.fill"

    /// Nothing is under way, so there is nothing to show.
    static let idle = BrowserSoftwareUpdatePhase(
        kind: .idle, name: "idle", title: "Software Update", statusLabel: "Software Update")
    static let permission = BrowserSoftwareUpdatePhase(
        kind: .permission, name: "permission", title: "Keep Crest Up to Date", statusLabel: "Permission required")
    static let checking = BrowserSoftwareUpdatePhase(
        kind: .checking, name: "checking", title: "Checking for Updates", statusLabel: "Checking",
        showsMessage: false, isWorking: true, windowShowsActivity: true)
    static let available = BrowserSoftwareUpdatePhase(
        kind: .available, name: "available", title: "Update Available", statusLabel: "Ready to download",
        informationOnlyStatusLabel: "Website release", isTitledByUpdate: true)
    static let downloading = BrowserSoftwareUpdatePhase(
        kind: .downloading, name: "downloading", title: "Downloading Update", statusLabel: "Downloading",
        symbol: "arrow.down.circle.fill", showsMessage: false, isTransferring: true, isWorking: true)
    static let extracting = BrowserSoftwareUpdatePhase(
        kind: .extracting, name: "extracting", title: "Preparing Update", statusLabel: "Preparing",
        showsMessage: false, isTransferring: true, isWorking: true, windowShowsActivity: true)
    static let readyToInstall = BrowserSoftwareUpdatePhase(
        kind: .readyToInstall, name: "readyToInstall", title: "Ready to Install", statusLabel: "Ready to install",
        symbol: installSymbol)
    static let installing = BrowserSoftwareUpdatePhase(
        kind: .installing, name: "installing", title: "Installing Update", statusLabel: "Installing",
        symbol: installSymbol, isWorking: true, windowShowsActivity: true)
    static let upToDate = BrowserSoftwareUpdatePhase(
        kind: .upToDate, name: "upToDate", title: "Crest Is Up to Date", statusLabel: "Up to date",
        symbol: settledSymbol, tone: .success)
    static let failed = BrowserSoftwareUpdatePhase(
        kind: .failed, name: "failed", title: "Update Check Failed", statusLabel: "Update error",
        symbol: "exclamationmark.triangle.fill", tone: .warning)
    static let installed = BrowserSoftwareUpdatePhase(
        kind: .installed, name: "installed", title: "Update Installed", statusLabel: "Installed",
        symbol: settledSymbol, tone: .success)
    /// Updates can't run in this build at all.
    static let unavailable = BrowserSoftwareUpdatePhase(
        kind: .unavailable, name: "unavailable", title: "Software Update Unavailable", statusLabel: "Unavailable")

    /// Every phase, in the order an update moves through them.
    static let all: [BrowserSoftwareUpdatePhase] = [
        idle, permission, checking, available, downloading, extracting, readyToInstall, installing, upToDate, failed,
        installed, unavailable,
    ]

    // MARK: - Variables

    let kind: Kinds
    let name: String
    let title: LocalizedStringResource

    /// Whether the update's own title, when it has one, stands in for the
    /// phase's.
    let isTitledByUpdate: Bool

    /// The phase in a word or two, beside the card's progress.
    let statusLabel: LocalizedStringResource

    /// The status of a release offered only on the website, where it differs.
    let informationOnlyStatusLabel: LocalizedStringResource?

    let symbol: String
    let tone: Tones

    /// Whether the card shows the update's message under the phase. A phase
    /// whose progress says enough leaves it out.
    let showsMessage: Bool

    /// Whether bytes are moving, so a measured progress has something to
    /// measure.
    let isTransferring: Bool

    /// Whether the card shows that work is under way.
    let isWorking: Bool

    /// Whether the update window shows work under way while it has no
    /// measured progress.
    let windowShowsActivity: Bool

    var id: String { name }

    // MARK: - Initializers

    private init(
        kind: Kinds, name: String, title: LocalizedStringResource, statusLabel: LocalizedStringResource,
        informationOnlyStatusLabel: LocalizedStringResource? = nil, isTitledByUpdate: Bool = false,
        symbol: String = BrowserSoftwareUpdatePhase.waitingSymbol, tone: Tones = .accent, showsMessage: Bool = true,
        isTransferring: Bool = false, isWorking: Bool = false, windowShowsActivity: Bool = false
    ) {
        self.kind = kind
        self.name = name
        self.title = title
        self.isTitledByUpdate = isTitledByUpdate
        self.statusLabel = statusLabel
        self.informationOnlyStatusLabel = informationOnlyStatusLabel
        self.symbol = symbol
        self.tone = tone
        self.showsMessage = showsMessage
        self.isTransferring = isTransferring
        self.isWorking = isWorking
        self.windowShowsActivity = windowShowsActivity
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSoftwareUpdatePhase, rhs: BrowserSoftwareUpdatePhase) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

struct BrowserSoftwareUpdateWidgetSnapshot: Equatable, Sendable {
    let phase: BrowserSoftwareUpdatePhase
    let title: String
    let version: String?
    let build: String?
    let releaseNotes: String?
    let informationURL: URL?
    let message: String?
    let progress: Double?
    let isInformationOnly: Bool
    let allowsInstallation: Bool
    let allowsSkipping: Bool
    let allowsCancellation: Bool
    let allowsInstallAndRelaunch: Bool
    let allowsInstallationRetry: Bool
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
    case viewUpdateInformation
    case dismissExactUpdate
    case cancelUpdate
    case installAndRelaunch
    case retryUpdateInstallation
    case declineAutomaticUpdateChecks
    case enableAutomaticUpdateChecks
    case acknowledgeUpdateStatus
}

struct BrowserSidebarWidgetInstance: Equatable, Identifiable, Sendable {
    let id: BrowserSidebarWidgetID
    let scope: BrowserSidebarWidgetScope
    let orderingOrdinal: UInt64
    let presentation: BrowserSidebarWidgetPresentation
    let availableActions: Set<BrowserSidebarWidgetAction>
}
