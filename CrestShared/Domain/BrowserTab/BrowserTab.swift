import Foundation

struct BrowserTab: Codable, Equatable, Identifiable, Sendable {
    static let startPageTitle = "Start Page"
    static let startPageSymbol = "flag.fill"
    private static let emojiSymbolPrefix = "crest.emoji:"

    let id: TabID
    var title: String
    var url: URL?
    var savedURL: URL?
    var symbol: String
    var faviconData: Data? {
        didSet { faviconPayloadIdentity = Self.payloadIdentity(for: faviconData) }
    }

    /// A fixed-size fingerprint of `faviconData`, refreshed whenever those bytes
    /// are assigned. The favicon render path needs an exact payload identity on
    /// every SwiftUI view update; reading it from here is what keeps that identity
    /// from hashing an image buffer on the main actor. Derived, transient, and not
    /// part of the stored session — see `CodingKeys`.
    private(set) var faviconPayloadIdentity: BrowserFaviconPayloadIdentity?
    var faviconURL: URL?
    var iconAccent: BrowserTabIconAccent?
    private var storedIconMode: BrowserTabIconMode?
    var placement: TabPlacement
    var folderID: FolderID?
    /// The split group this tab is a member of. A group is the maximal
    /// contiguous run of tabs sharing this value, so the field is a parent
    /// pointer exactly like `folderID` rather than a second collection.
    /// Optional so sessions written before 0.4 continue to decode safely.
    var splitGroupID: SplitGroupID?
    var lastActivatedAt: Date
    /// Wall-clock time of the last user-visible move. Optional so sessions
    /// written before position-aware sync continue to decode safely.
    var positionModifiedAt: Date?
    /// Name the person gave this tab. It layers over the observed page title
    /// rather than replacing it, so clearing the rename returns the tab to
    /// tracking whatever the page reports. Optional so sessions written before
    /// tab renaming continue to decode safely.
    var customTitle: String?
    /// Wall-clock time of the last rename, including the rename that cleared
    /// one. Optional for the same reason as `positionModifiedAt`.
    var titleModifiedAt: Date?
    /// A person-controlled exception to automatic memory-pressure unloading.
    /// Explicit unloading still wins, so this is a residency preference rather
    /// than an ownership promise WebKit cannot keep under process termination.
    var keepsPageLoaded: Bool

    init(
        id: TabID = TabID(),
        title: String,
        url: URL?,
        savedURL: URL? = nil,
        symbol: String = "globe",
        faviconData: Data? = nil,
        faviconURL: URL? = nil,
        iconAccent: BrowserTabIconAccent? = nil,
        iconMode: BrowserTabIconMode? = nil,
        placement: TabPlacement,
        folderID: FolderID? = nil,
        splitGroupID: SplitGroupID? = nil,
        lastActivatedAt: Date = .now,
        positionModifiedAt: Date? = nil,
        customTitle: String? = nil,
        titleModifiedAt: Date? = nil,
        keepsPageLoaded: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.savedURL = savedURL ?? (placement == .current ? nil : url)
        self.symbol = symbol
        self.faviconData = faviconData
        // Property observers do not run inside an initializer.
        faviconPayloadIdentity = Self.payloadIdentity(for: faviconData)
        self.faviconURL = faviconURL ?? (faviconData == nil ? nil : url)
        self.iconAccent = iconAccent
        storedIconMode = iconMode
        self.placement = placement
        self.folderID = folderID
        self.splitGroupID = splitGroupID
        self.lastActivatedAt = lastActivatedAt
        self.positionModifiedAt = positionModifiedAt.map(Self.normalizedTimestamp)
        self.customTitle = Self.resolvedCustomTitle(customTitle)
        self.titleModifiedAt = titleModifiedAt.map(Self.normalizedTimestamp)
        self.keepsPageLoaded = keepsPageLoaded
    }

    static func startPage(
        id: TabID = TabID(),
        placement: TabPlacement = .current,
        lastActivatedAt: Date = .now
    ) -> BrowserTab {
        BrowserTab(
            id: id,
            title: startPageTitle,
            url: nil,
            symbol: startPageSymbol,
            placement: placement,
            lastActivatedAt: lastActivatedAt
        )
    }

    var isStartPage: Bool {
        url == nil
    }

    var savedSiteURL: URL? {
        savedURL ?? (placement == .current ? nil : url)
    }

    var supportsSavedLocationEditing: Bool {
        placement != .current && savedSiteURL != nil
    }

    var isAwayFromSavedLocation: Bool {
        guard supportsSavedLocationEditing,
            let url,
            let savedSiteURL
        else { return false }
        let current = BrowserHistoryURL.normalized(url) ?? url
        let saved = BrowserHistoryURL.normalized(savedSiteURL) ?? savedSiteURL
        return current != saved
    }

    var emojiIcon: String? {
        guard symbol.hasPrefix(Self.emojiSymbolPrefix) else { return nil }
        let emoji = String(symbol.dropFirst(Self.emojiSymbolPrefix.count))
        return emoji.isEmpty ? nil : emoji
    }

    static func symbol(forEmoji emoji: String) -> String {
        emojiSymbolPrefix + emoji
    }

    mutating func markPositionModified(at date: Date) {
        positionModifiedAt = Self.normalizedTimestamp(date)
    }

    mutating func markTitleModified(at date: Date) {
        titleModifiedAt = Self.normalizedTimestamp(date)
    }

    private static func normalizedTimestamp(_ date: Date) -> Date {
        let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded()
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    /// The name every tab surface renders. A rename wins over the page title;
    /// an absent or blank one hands the tab back to the page, including a blank
    /// that reached this device through storage or sync rather than the field.
    var displayTitle: String {
        Self.resolvedCustomTitle(customTitle) ?? title
    }

    /// Trims a proposed rename and folds a blank one back to "no rename", so a
    /// committed empty field is how someone clears the name they chose.
    static func resolvedCustomTitle(_ title: String?) -> String? {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    var iconMode: BrowserTabIconMode {
        get {
            if let storedIconMode { return storedIconMode }
            return emojiIcon == nil ? .automatic : .emoji
        }
        set { storedIconMode = newValue }
    }

    var displayFaviconData: Data? {
        switch iconMode {
        case .emoji:
            return nil
        case .pulled:
            return faviconData
        case .automatic:
            return faviconData
        }
    }

    /// The fingerprint of whatever `displayFaviconData` would hand back. The
    /// favicon render path reads this instead of the bytes, which is what keeps a
    /// view update free of image hashing.
    var displayFaviconPayloadIdentity: BrowserFaviconPayloadIdentity? {
        displayFaviconData == nil ? nil : faviconPayloadIdentity
    }

    var hasCurrentAutomaticFavicon: Bool {
        guard iconMode == .automatic,
            faviconData != nil,
            let faviconURL,
            let url
        else { return false }
        let cached = BrowserHistoryURL.normalized(faviconURL) ?? faviconURL
        let current = BrowserHistoryURL.normalized(url) ?? url
        return cached == current
    }

    private static func payloadIdentity(for data: Data?) -> BrowserFaviconPayloadIdentity? {
        data.map(BrowserFaviconPayloadIdentity.init(hashing:))
    }

    /// Exactly the terms the synthesized `Codable` used, so nothing about the
    /// stored or synchronized shape of a tab changes. `faviconPayloadIdentity` is
    /// absent on purpose: it is derived from `faviconData`, and a stored copy could
    /// only ever go stale.
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case savedURL
        case symbol
        case faviconData
        case faviconURL
        case iconAccent
        case storedIconMode
        case placement
        case folderID
        case splitGroupID
        case lastActivatedAt
        case positionModifiedAt
        case customTitle
        case titleModifiedAt
        case keepsPageLoaded
    }

    /// Decodes a tab written by any build, including one that knows placements or
    /// icon modes this build does not.
    ///
    /// A synthesized `Codable` throws on an unfamiliar raw value, and one throw
    /// here fails the entire `BrowserSession` decode — which is how a rollback, a
    /// second Mac, or one new enum case turns into an unreadable session. Every
    /// vocabulary term below therefore resolves rather than throws.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(TabID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        savedURL = try container.decodeIfPresent(URL.self, forKey: .savedURL)
        symbol = try container.decode(String.self, forKey: .symbol)
        let decodedFavicon = try container.decodeIfPresent(Data.self, forKey: .faviconData)
        faviconData = decodedFavicon
        faviconPayloadIdentity = Self.payloadIdentity(for: decodedFavicon)
        faviconURL = try container.decodeIfPresent(URL.self, forKey: .faviconURL)
        iconAccent = try container.decodeIfPresent(
            BrowserTabIconAccent.self,
            forKey: .iconAccent
        )
        // An icon mode this build cannot name resolves to "no stored mode", so
        // `iconMode` derives it from the tab's own symbol exactly as it does for
        // every tab written before modes were stored at all. Defaulting to a
        // concrete mode instead would pin the tab to that mode forever.
        let storedIconTerm = try? container.decodeIfPresent(
            String.self,
            forKey: .storedIconMode
        )
        storedIconMode =
            storedIconTerm
            .flatMap { $0 }
            .flatMap(BrowserTabIconMode.init(rawValue:))
        // `.saved` is the placement that preserves an unfamiliar tab most
        // faithfully: a saved tab keeps its address, is never swept by current-tab
        // cleanup, and is not subject to the pinned-tab limit.
        placement = container.decodeTolerantly(.placement, default: .saved)
        folderID = try container.decodeIfPresent(FolderID.self, forKey: .folderID)
        splitGroupID = try container.decodeIfPresent(
            SplitGroupID.self,
            forKey: .splitGroupID
        )
        lastActivatedAt = try container.decode(Date.self, forKey: .lastActivatedAt)
        positionModifiedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .positionModifiedAt
        )
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        titleModifiedAt = try container.decodeIfPresent(Date.self, forKey: .titleModifiedAt)
        keepsPageLoaded =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .keepsPageLoaded
            ) ?? false
    }
}
