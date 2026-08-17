import Foundation

struct BrowserTabSessionDraft: Equatable, Sendable {
    let sourceOrdinal: Int
    let name: String?
    let folders: [BrowserTabSessionFolderDraft]
    let tabs: [BrowserTabSessionTabDraft]
    let selectedTabIndex: Int?
    let symbol: String?
    let accent: SpaceAccent?
    let branding: BrowserSpaceBranding?

    init(
        sourceOrdinal: Int,
        name: String?,
        tabs: [BrowserTabSessionTabDraft],
        selectedTabIndex: Int?,
        folders: [BrowserTabSessionFolderDraft] = [],
        symbol: String? = nil,
        accent: SpaceAccent? = nil,
        branding: BrowserSpaceBranding? = nil
    ) {
        self.sourceOrdinal = sourceOrdinal
        self.name = name
        self.folders = folders
        self.tabs = tabs
        self.selectedTabIndex = selectedTabIndex
        self.symbol = symbol
        self.accent = accent
        self.branding = branding
    }
}

struct BrowserTabSessionFolderDraft: Equatable, Sendable {
    let sourceID: String
    let title: String
    let parentSourceID: String?
}

struct BrowserTabSessionTabDraft: Equatable, Sendable {
    let title: String
    let url: URL
    let placement: TabPlacement
    let folderSourceID: String?
    let lastActivatedAt: Date

    init(
        title: String,
        url: URL,
        isPinned: Bool,
        lastActivatedAt: Date
    ) {
        self.title = title
        self.url = url
        placement = isPinned ? .pinned : .current
        folderSourceID = nil
        self.lastActivatedAt = lastActivatedAt
    }

    init(
        title: String,
        url: URL,
        placement: TabPlacement,
        folderSourceID: String? = nil,
        lastActivatedAt: Date
    ) {
        self.title = title
        self.url = url
        self.placement = placement
        self.folderSourceID = placement == .saved ? folderSourceID : nil
        self.lastActivatedAt = lastActivatedAt
    }
}

enum BrowserTabMigrationError: LocalizedError, Equatable, Sendable {
    case fileTooLarge
    case invalidContents
    case encryptedChromiumSession
    case noImportableTabs
    case resourceLimitExceeded

    var errorDescriptionResource: LocalizedStringResource {
        switch self {
        case .fileTooLarge:
            "This session file is larger than Crest’s 512 MB import limit."
        case .invalidContents:
            "Crest could not recognize this browser’s tab-session data."
        case .encryptedChromiumSession:
            "This Chromium session is profile-encrypted and cannot be safely imported outside its source browser."
        case .noImportableTabs:
            "This session has no HTTP or HTTPS tabs Crest can import."
        case .resourceLimitExceeded:
            "This session exceeds Crest’s tab, window, text, or decompression limits."
        }
    }

    var errorDescription: String? {
        String(localized: errorDescriptionResource)
    }
}
