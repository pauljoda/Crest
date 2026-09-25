import Foundation

struct BrowserLinkPreferences: Codable, Equatable, Sendable {
    var externalLinkDestination: ExternalLinkDestination
    var externalLinkSpaceID: SpaceID?
    var focusesNewTabsOpenedFromLinks: Bool
    var followsTabsMovedToAnotherSpace: Bool
    var automaticallyOpensPeek: Bool
    var peekClickModifier: LinkPeekModifier
    var dragsLinksToPeek: Bool
    var quickWindowArchivePolicy: QuickWindowArchivePolicy
    var remembersQuickWindowSpaceBySite: Bool
    var routes: [BrowserLinkRoute]
    var rememberedQuickWindowSpacesBySite: [String: SpaceID]

    static let `default` = BrowserLinkPreferences(
        externalLinkDestination: .quickWindow,
        externalLinkSpaceID: nil,
        focusesNewTabsOpenedFromLinks: false,
        automaticallyOpensPeek: true,
        peekClickModifier: .option,
        quickWindowArchivePolicy: .after6Hours,
        remembersQuickWindowSpaceBySite: true,
        routes: [],
        rememberedQuickWindowSpacesBySite: [:]
    )

    private enum CodingKeys: String, CodingKey {
        case externalLinkDestination
        case externalLinkSpaceID
        case focusesNewTabsOpenedFromLinks
        case followsTabsMovedToAnotherSpace
        case automaticallyOpensPeek
        case peekClickModifier
        case dragsLinksToPeek
        case quickWindowArchivePolicy
        case remembersQuickWindowSpaceBySite
        case routes
        case rememberedQuickWindowSpacesBySite
    }

    init(
        externalLinkDestination: ExternalLinkDestination,
        externalLinkSpaceID: SpaceID?,
        focusesNewTabsOpenedFromLinks: Bool,
        automaticallyOpensPeek: Bool,
        peekClickModifier: LinkPeekModifier,
        quickWindowArchivePolicy: QuickWindowArchivePolicy,
        remembersQuickWindowSpaceBySite: Bool,
        routes: [BrowserLinkRoute],
        rememberedQuickWindowSpacesBySite: [String: SpaceID],
        followsTabsMovedToAnotherSpace: Bool = true,
        dragsLinksToPeek: Bool = true
    ) {
        self.externalLinkDestination = externalLinkDestination
        self.externalLinkSpaceID = externalLinkSpaceID
        self.focusesNewTabsOpenedFromLinks = focusesNewTabsOpenedFromLinks
        self.followsTabsMovedToAnotherSpace = followsTabsMovedToAnotherSpace
        self.automaticallyOpensPeek = automaticallyOpensPeek
        self.peekClickModifier = peekClickModifier
        self.dragsLinksToPeek = dragsLinksToPeek
        self.quickWindowArchivePolicy = quickWindowArchivePolicy
        self.remembersQuickWindowSpaceBySite = remembersQuickWindowSpaceBySite
        self.routes = routes
        self.rememberedQuickWindowSpacesBySite = rememberedQuickWindowSpacesBySite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        externalLinkDestination =
            try container.decodeIfPresent(
                ExternalLinkDestination.self,
                forKey: .externalLinkDestination
            ) ?? .quickWindow
        externalLinkSpaceID = try container.decodeIdentityIfPresent(forKey: .externalLinkSpaceID)
        focusesNewTabsOpenedFromLinks =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .focusesNewTabsOpenedFromLinks
            ) ?? false
        followsTabsMovedToAnotherSpace =
            try container.decodeIfPresent(Bool.self, forKey: .followsTabsMovedToAnotherSpace) ?? true
        automaticallyOpensPeek =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .automaticallyOpensPeek
            ) ?? true
        peekClickModifier =
            try container.decodeIfPresent(
                LinkPeekModifier.self,
                forKey: .peekClickModifier
            ) ?? .option
        dragsLinksToPeek = try container.decodeIfPresent(Bool.self, forKey: .dragsLinksToPeek) ?? true
        quickWindowArchivePolicy =
            try container.decodeIfPresent(
                QuickWindowArchivePolicy.self,
                forKey: .quickWindowArchivePolicy
            ) ?? .after6Hours
        remembersQuickWindowSpaceBySite =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .remembersQuickWindowSpaceBySite
            ) ?? true
        routes =
            try container.decodeIfPresent(
                [BrowserLinkRoute].self,
                forKey: .routes
            ) ?? []
        rememberedQuickWindowSpacesBySite =
            try container.decodeIdentitiesByNameIfPresent(forKey: .rememberedQuickWindowSpacesBySite) ?? [:]
    }

    /// The defaults keep these preferences, so their Spaces keep the stored
    /// identity spelling a build before S6.2 reads.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(externalLinkDestination, forKey: .externalLinkDestination)
        try container.encodeStoredIdentityIfPresent(externalLinkSpaceID, forKey: .externalLinkSpaceID)
        try container.encode(focusesNewTabsOpenedFromLinks, forKey: .focusesNewTabsOpenedFromLinks)
        try container.encode(followsTabsMovedToAnotherSpace, forKey: .followsTabsMovedToAnotherSpace)
        try container.encode(automaticallyOpensPeek, forKey: .automaticallyOpensPeek)
        try container.encode(peekClickModifier, forKey: .peekClickModifier)
        try container.encode(dragsLinksToPeek, forKey: .dragsLinksToPeek)
        try container.encode(quickWindowArchivePolicy, forKey: .quickWindowArchivePolicy)
        try container.encode(remembersQuickWindowSpaceBySite, forKey: .remembersQuickWindowSpaceBySite)
        try container.encode(routes, forKey: .routes)
        try container.encodeStoredIdentitiesByName(
            rememberedQuickWindowSpacesBySite, forKey: .rememberedQuickWindowSpacesBySite)
    }
}
