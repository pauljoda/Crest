import Foundation

enum BrowserSpaceBrandingPreviewFixture {
    static let bannerBranding = BrowserSpaceBranding(
        colors: BrowserSpaceHousePalette.winter.colors,
        bannerPattern: .diagonal,
        bannerStrength: 1,
        readabilityFade: BrowserSpaceBranding.initialReadabilityFade,
        themeMode: .banner,
        iconStyle: .simpleSymbol
    )

    static let gradientBranding = BrowserSpaceBranding(
        colors: BrowserSpaceHousePalette.storm.colors,
        bannerStrength: 0.82,
        readabilityFade: 0.2,
        themeMode: .gradient,
        gradientAngle: 127,
        showsTexture: true,
        iconStyle: .simpleSymbol
    )

    static let crestBranding = BrowserSpaceBranding(
        colors: BrowserSpaceHousePalette.lion.colors,
        bannerPattern: .quartered,
        bannerStrength: 1,
        readabilityFade: BrowserSpaceBranding.initialReadabilityFade,
        themeMode: .banner,
        iconStyle: .layeredCrest,
        crest: BrowserSpaceCrest(
            backplate: .shield,
            fieldDivision: .quarterly,
            ordinary: .bend,
            trim: .laurel,
            symbol: .crown,
            chargeLayout: .trio,
            backplateColorIndex: 1,
            secondaryFieldColorIndex: 0,
            ordinaryColorIndex: 2,
            trimColorIndex: 2,
            symbolColorIndex: 2
        )
    )

    static let simpleSpace = makeSpace(
        idByte: 0x11,
        profileByte: 0x21,
        name: "Winter",
        symbol: "snowflake",
        accent: .indigo,
        branding: bannerBranding,
        accessPolicy: .open
    )

    static let crestSpace = makeSpace(
        idByte: 0x12,
        profileByte: 0x22,
        name: "Lion",
        symbol: "crown.fill",
        accent: .orange,
        branding: crestBranding,
        accessPolicy: .deviceOwnerAuthentication
    )

    private static func makeSpace(
        idByte: UInt8,
        profileByte: UInt8,
        name: String,
        symbol: String,
        accent: SpaceAccent,
        branding: BrowserSpaceBranding,
        accessPolicy: BrowserSpaceAccessPolicy
    ) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(rawValue: deterministicUUID(finalByte: idByte)),
            profile: BrowsingProfile(id: deterministicUUID(finalByte: profileByte)),
            name: name,
            symbol: symbol,
            accent: accent,
            branding: branding,
            folders: [],
            tabs: [],
            accessPolicy: accessPolicy,
            selectedTabID: nil
        )
    }

    private static func deterministicUUID(finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x53,
                0x50, 0x41,
                0x43, 0x45,
                0x42, 0x52, 0x41, 0x4E, 0x44, finalByte
            ))
    }
}
