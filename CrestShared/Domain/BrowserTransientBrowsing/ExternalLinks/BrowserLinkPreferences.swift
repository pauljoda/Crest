import Foundation

enum BrowserExternalLinkDestination:
    String,
    Codable,
    CaseIterable,
    Equatable,
    Identifiable,
    Sendable
{
    case quickWindow
    case mostRecentSpace
    case chosenSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickWindow: "Quick Window"
        case .mostRecentSpace: "Most Recent Space"
        case .chosenSpace: "Chosen Space"
        }
    }
}

struct BrowserLinkPreferences: Codable, Equatable, Sendable {
    var externalLinkDestination: BrowserExternalLinkDestination
    var externalLinkSpaceID: SpaceID?
    var focusesNewTabsOpenedFromLinks: Bool
    var automaticallyOpensPeek: Bool
    var peekClickModifier: BrowserLinkClickModifier
    var quickWindowArchivePolicy: BrowserQuickWindowArchivePolicy
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
        case automaticallyOpensPeek
        case peekClickModifier
        case quickWindowArchivePolicy
        case remembersQuickWindowSpaceBySite
        case routes
        case rememberedQuickWindowSpacesBySite
    }

    init(
        externalLinkDestination: BrowserExternalLinkDestination,
        externalLinkSpaceID: SpaceID?,
        focusesNewTabsOpenedFromLinks: Bool,
        automaticallyOpensPeek: Bool,
        peekClickModifier: BrowserLinkClickModifier,
        quickWindowArchivePolicy: BrowserQuickWindowArchivePolicy,
        remembersQuickWindowSpaceBySite: Bool,
        routes: [BrowserLinkRoute],
        rememberedQuickWindowSpacesBySite: [String: SpaceID]
    ) {
        self.externalLinkDestination = externalLinkDestination
        self.externalLinkSpaceID = externalLinkSpaceID
        self.focusesNewTabsOpenedFromLinks = focusesNewTabsOpenedFromLinks
        self.automaticallyOpensPeek = automaticallyOpensPeek
        self.peekClickModifier = peekClickModifier
        self.quickWindowArchivePolicy = quickWindowArchivePolicy
        self.remembersQuickWindowSpaceBySite = remembersQuickWindowSpaceBySite
        self.routes = routes
        self.rememberedQuickWindowSpacesBySite = rememberedQuickWindowSpacesBySite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        externalLinkDestination =
            try container.decodeIfPresent(
                BrowserExternalLinkDestination.self,
                forKey: .externalLinkDestination
            ) ?? .quickWindow
        externalLinkSpaceID = try container.decodeIfPresent(
            SpaceID.self,
            forKey: .externalLinkSpaceID
        )
        focusesNewTabsOpenedFromLinks =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .focusesNewTabsOpenedFromLinks
            ) ?? false
        automaticallyOpensPeek =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .automaticallyOpensPeek
            ) ?? true
        peekClickModifier =
            try container.decodeIfPresent(
                BrowserLinkClickModifier.self,
                forKey: .peekClickModifier
            ) ?? .option
        quickWindowArchivePolicy =
            try container.decodeIfPresent(
                BrowserQuickWindowArchivePolicy.self,
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
            try container.decodeIfPresent(
                [String: SpaceID].self,
                forKey: .rememberedQuickWindowSpacesBySite
            ) ?? [:]
    }
}
