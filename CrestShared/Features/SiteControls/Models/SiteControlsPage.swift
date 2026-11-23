import Foundation

/// A page Site Controls open over their root, which shows one part of the
/// site whole: its title, its title while it edits what it lists, whether it
/// is about the site rather than every site, and the kind
/// ``SiteControlsPageRouter`` draws.
struct SiteControlsPage: Hashable, Sendable {
    // MARK: - Types

    /// The pages there are, which the router turns into their rows.
    enum Kind: Hashable, Sendable {
        case connection
        case blocking
        case permissions
        case extensions
        case siteData
        case downloads
        case translate
        case actions
        case qrCode
    }

    // MARK: - Static Variables

    static let connection = SiteControlsPage(.connection, title: "Connection")
    static let blocking = SiteControlsPage(.blocking, title: "Ads and Trackers")
    static let permissions = SiteControlsPage(.permissions, title: "Permissions")
    static let extensions = SiteControlsPage(.extensions, title: "Extensions", isAboutSite: false)
    static let siteData = SiteControlsPage(.siteData, title: "Site Data")
    static let downloads = SiteControlsPage(.downloads, title: "Downloads", isAboutSite: false)
    static let translate = SiteControlsPage(.translate, title: "Translate")
    static let actions = SiteControlsPage(
        .actions, title: "More Actions", editingTitle: "Edit Actions", isAboutSite: false)
    static let qrCode = SiteControlsPage(.qrCode, title: "QR Code")

    // MARK: - Variables

    let kind: Kind
    let title: LocalizedStringResource
    /// The title while the page edits what it lists, or nil for a page that
    /// edits nothing.
    let editingTitle: LocalizedStringResource?
    /// Whether the page is about the site, so it names the site's host under
    /// its title; one that is the same on every site, such as the actions,
    /// names none.
    let isAboutSite: Bool

    // MARK: - Initializers

    private init(
        _ kind: Kind, title: LocalizedStringResource, editingTitle: LocalizedStringResource? = nil,
        isAboutSite: Bool = true
    ) {
        self.kind = kind
        self.title = title
        self.editingTitle = editingTitle
        self.isAboutSite = isAboutSite
    }

    // MARK: - Equatable

    static func == (lhs: SiteControlsPage, rhs: SiteControlsPage) -> Bool { lhs.kind == rhs.kind }

    func hash(into hasher: inout Hasher) { hasher.combine(kind) }
}
