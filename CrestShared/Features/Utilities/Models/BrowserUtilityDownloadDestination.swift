import Foundation

/// Where a finished download can go from its row.
struct BrowserUtilityDownloadDestination: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// Each destination hands the file to a different part of the system, so
    /// the shell that opens a download switches over the kind.
    enum Kinds: Sendable {
        case open
        case revealInFinder
        case share
        case files
    }

    // MARK: - Static Variables

    static let open = BrowserUtilityDownloadDestination(
        kind: .open, name: "open", title: "Open", symbol: "arrow.up.forward.square")
    static let revealInFinder = BrowserUtilityDownloadDestination(
        kind: .revealInFinder, name: "revealInFinder", title: "Show in Finder", symbol: "magnifyingglass")
    static let share = BrowserUtilityDownloadDestination(
        kind: .share, name: "share", title: "Share…", symbol: "square.and.arrow.up")
    static let files = BrowserUtilityDownloadDestination(
        kind: .files, name: "files", title: "Save to Files…", symbol: "folder.badge.plus")

    /// Every destination.
    static let all: [BrowserUtilityDownloadDestination] = [open, revealInFinder, share, files]

    // MARK: - Variables

    let kind: Kinds
    let name: String
    let title: LocalizedStringResource
    let symbol: String

    var id: String { name }

    // MARK: - Initializers

    private init(kind: Kinds, name: String, title: LocalizedStringResource, symbol: String) {
        self.kind = kind
        self.name = name
        self.title = title
        self.symbol = symbol
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserUtilityDownloadDestination, rhs: BrowserUtilityDownloadDestination) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

enum BrowserUtilityDownloadPrimaryActionPolicy {
    static func destination(
        for state: DownloadPhase,
        availableDestinations: [BrowserUtilityDownloadDestination]
    ) -> BrowserUtilityDownloadDestination? {
        guard state.isComplete,
            availableDestinations.contains(.revealInFinder)
        else { return nil }
        return .revealInFinder
    }
}
