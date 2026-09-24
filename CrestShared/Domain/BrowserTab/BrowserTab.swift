import Foundation

struct BrowserTab: Codable, Equatable, Identifiable, Sendable {
    static let startPageTitle = "Start Page"
    static let startPageSymbol = "flag.fill"

    let id: TabID
    var title: String
    private(set) var nativeContent: BrowserNativeTabContent?
    var url: URL? {
        didSet { if url != nil { nativeContent = nil } }
    }
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
    private var storedIconMode: TabIconMode?
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
        nativeContent: BrowserNativeTabContent? = nil,
        savedURL: URL? = nil,
        symbol: String = "globe",
        faviconData: Data? = nil,
        faviconURL: URL? = nil,
        iconAccent: BrowserTabIconAccent? = nil,
        iconMode: TabIconMode? = nil,
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
        self.nativeContent = nativeContent
        self.url = nativeContent == nil ? url : nil
        self.savedURL = nativeContent == nil ? (savedURL ?? (!placement.isDurable ? nil : url)) : nil
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

    /// TRANSITIONAL until S6.1 retires the Swift session copy: a tab as the
    /// core publishes it, read the way the decoder reads the core's stored
    /// form, wearing `faviconData`, the image the copy keeps for it. Edit
    /// clocks take the spelling that form gives a whole millisecond.
    init(core state: TabState, faviconData: Data?) {
        id = TabID(rawValue: state.id)
        title = state.title
        nativeContent = state.nativeContent.map { BrowserNativeTabContent(kind: $0.kind, resourceID: $0.resourceID) }
        url = state.nativeContent == nil ? state.url.flatMap(URL.init(string:)) : nil
        savedURL = state.nativeContent == nil ? state.savedURL.flatMap(URL.init(string:)) : nil
        symbol = state.symbol
        self.faviconData = faviconData
        faviconPayloadIdentity = Self.payloadIdentity(for: faviconData)
        faviconURL = state.faviconURL.flatMap(URL.init(string:))
        iconAccent = state.iconAccent.map { BrowserTabIconAccent(red: $0.red, green: $0.green, blue: $0.blue) }
        storedIconMode = state.storedIconMode
        placement = state.placement
        folderID = state.folderID.map(FolderID.init(rawValue:))
        splitGroupID = state.splitGroupID.map(SplitGroupID.init(rawValue:))
        lastActivatedAt = state.lastActivatedAt
        positionModifiedAt = state.positionModifiedAt.map(Self.storedEditClock)
        customTitle = state.customTitle
        titleModifiedAt = state.titleModifiedAt.map(Self.storedEditClock)
        keepsPageLoaded = state.keepsPageLoaded
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
        nativeContent == nil && url == nil
    }

    var isWebPage: Bool { nativeContent == nil && url != nil }

    var savedSiteURL: URL? {
        savedURL ?? (!placement.isDurable ? nil : url)
    }

    var supportsSavedLocationEditing: Bool {
        placement.isDurable && savedSiteURL != nil
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
        BrowserIconSymbol.emoji(from: symbol)
    }

    static func symbol(forEmoji emoji: String) -> String {
        BrowserIconSymbol.symbol(forEmoji: emoji)
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

    /// TRANSITIONAL until S6.1: an edit clock as the core's stored form spells
    /// it. A whole millisecond takes this type's own arithmetic, so the copy
    /// holds the same bits a decoded session does; any other time stays as it
    /// came.
    private static func storedEditClock(_ date: Date) -> Date {
        let normalized = normalizedTimestamp(date)
        return abs(normalized.timeIntervalSince(date)) < 0.000_001 ? normalized : date
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

    var iconMode: TabIconMode {
        get { storedIconMode ?? .inferred(from: symbol) }
        set { storedIconMode = newValue }
    }

    var displayFaviconData: Data? {
        iconMode.showsFavicon ? faviconData : nil
    }

    /// The fingerprint of whatever `displayFaviconData` would hand back. The
    /// favicon render path reads this instead of the bytes, which is what keeps a
    /// view update free of image hashing.
    var displayFaviconPayloadIdentity: BrowserFaviconPayloadIdentity? {
        displayFaviconData == nil ? nil : faviconPayloadIdentity
    }

    var hasCurrentAutomaticFavicon: Bool {
        guard iconMode.followsPage,
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

    /// Stored fields include the optional native descriptor. The derived
    /// favicon payload identity is rebuilt when decoding rather than persisted.
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case nativeContent
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
        nativeContent = try container.decodeIfPresent(BrowserNativeTabContent.self, forKey: .nativeContent)
        url = nativeContent == nil ? try container.decodeIfPresent(URL.self, forKey: .url) : nil
        savedURL = nativeContent == nil ? try container.decodeIfPresent(URL.self, forKey: .savedURL) : nil
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
            .flatMap(TabIconMode.named)
        // `.saved` is the placement that preserves an unfamiliar tab most
        // faithfully: a saved tab keeps its address, is never swept by current-tab
        // cleanup, and is not subject to the pinned-tab limit.
        placement = (try? container.decodeIfPresent(TabPlacement.self, forKey: .placement)).flatMap { $0 } ?? .saved
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

/// The storage boundary shared by every browser entity that can wear an emoji.
///
/// An emoji is stored in the same `symbol` slot as an SF Symbol, with a prefix
/// that makes the two vocabularies unambiguous. Normalization selects one
/// Swift `Character`, not one Unicode scalar, so flags, skin tones, keycaps,
/// and zero-width-joiner sequences survive as the complete grapheme a person
/// picked.
enum BrowserIconSymbol {
    static func symbol(forEmoji input: String) -> String {
        guard let emoji = normalizedEmoji(input) else { return input }
        return TabIconMode.emojiPrefix + emoji
    }

    static func emoji(from symbol: String) -> String? {
        guard symbol.hasPrefix(TabIconMode.emojiPrefix) else { return nil }
        return normalizedEmoji(String(symbol.dropFirst(TabIconMode.emojiPrefix.count)))
    }

    static func normalizedEmoji(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let character = trimmed.first else { return nil }
        let candidate = String(character)
        let scalars = candidate.unicodeScalars
        let isEmoji = scalars.contains { scalar in
            scalar.properties.isEmojiPresentation
                || scalar.value == 0xFE0F
                || scalar.value == 0x20E3
        }
        return isEmoji ? candidate : nil
    }
}
