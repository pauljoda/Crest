import Foundation

struct BrowserSpaceBranding: Codable, Equatable, Sendable {
    static let maximumColorCount = 3
    static let initialReadabilityFade = 0.45

    /// The vocabulary the currently shipped build draws. Banner strengths stored
    /// at this version or above are already in today's units.
    static let baselineRenderingVersion = 2
    /// The vocabulary that adds the expanded heraldic charges.
    static let expandedChargeRenderingVersion = 3
    /// The newest vocabulary this build can produce.
    static let customizationRenderingVersion = 4
    static let currentRenderingVersion = customizationRenderingVersion

    var colors: [BrowserSpaceBrandColor]
    var bannerPattern: BrowserSpaceBannerPattern
    var bannerStrength: Double
    var readabilityFade: Double
    var themeMode: BrowserSpaceThemeMode
    var gradientAngle: Double
    var showsTexture: Bool
    var iconStyle: BrowserSpaceIconStyle
    /// Nil follows the Space palette as it changes.
    var symbolColor: BrowserSpaceBrandColor?
    var crest: BrowserSpaceCrest
    var folderColorIntensity: Double
    var textColorMode: BrowserSpaceTextColorMode
    /// Nil belongs to older Spaces and is inferred from their stored appearance.
    /// Explicit editing keeps returning to customization, even if a later edit
    /// happens to recreate the original template exactly.
    var hasCustomAppearance: Bool?

    var keepsControlsReadable: Bool {
        get { readabilityFade > 0 }
        set { readabilityFade = newValue ? max(readabilityFade, 0.25) : 0 }
    }

    /// The rendering vocabulary this branding needs, and the version it encodes.
    ///
    /// Branding that uses only the shipped vocabulary keeps announcing the
    /// baseline, so nothing that already round-trips starts claiming a version its
    /// readers have never seen. Only branding that actually wears a newer charge
    /// moves the number.
    var renderingVersion: Int {
        max(
            bannerPattern.introducedInRenderingVersion, crest.requiredRenderingVersion,
            symbolColor != nil
                ? Self.customizationRenderingVersion : Self.baselineRenderingVersion)
    }

    init(
        colors: [BrowserSpaceBrandColor],
        bannerPattern: BrowserSpaceBannerPattern = .diagonal,
        bannerStrength: Double = 1,
        readabilityFade: Double? = nil,
        keepsControlsReadable: Bool = true,
        themeMode: BrowserSpaceThemeMode = .banner,
        gradientAngle: Double = 0,
        showsTexture: Bool = false,
        iconStyle: BrowserSpaceIconStyle = .simpleSymbol,
        symbolColor: BrowserSpaceBrandColor? = nil,
        crest: BrowserSpaceCrest = BrowserSpaceCrest(),
        folderColorIntensity: Double = 0,
        textColorMode: BrowserSpaceTextColorMode = .automatic,
        hasCustomAppearance: Bool? = nil
    ) {
        let normalizedColors =
            colors.isEmpty
            ? [.indigo]
            : Array(colors.prefix(Self.maximumColorCount))
        self.colors = normalizedColors
        self.bannerPattern = bannerPattern
        self.bannerStrength = min(max(bannerStrength, 0), 1)
        self.readabilityFade = min(
            max(readabilityFade ?? (keepsControlsReadable ? 0.25 : 0), 0),
            1
        )
        self.themeMode = themeMode
        self.gradientAngle = Self.normalizedGradientAngle(gradientAngle)
        self.showsTexture = showsTexture
        self.iconStyle = iconStyle
        self.symbolColor = symbolColor
        self.crest = crest.normalized(forColorCount: normalizedColors.count)
        self.folderColorIntensity = folderColorIntensity.isFinite ? min(max(folderColorIntensity, 0), 1) : 0
        self.textColorMode = textColorMode
        self.hasCustomAppearance = hasCustomAppearance
    }

    static func legacy(accent: SpaceAccent, symbol: String) -> BrowserSpaceBranding {
        let colors: [BrowserSpaceBrandColor]
        switch accent {
        case .indigo:
            colors = [.ink, .ocean, .gold]
        case .orange:
            colors = [.ember, .gold, .ocean]
        case .teal:
            colors = [.teal, .ocean, .sand]
        case .rose:
            colors = [.rose, .indigo, .sand]
        }
        return BrowserSpaceBranding(
            colors: colors,
            bannerPattern: .diagonal,
            bannerStrength: 1,
            keepsControlsReadable: true,
            iconStyle: .simpleSymbol,
            crest: BrowserSpaceCrest(symbol: crestSymbol(forLegacySymbol: symbol))
        )
    }

    static func initial(accent: SpaceAccent, symbol: String) -> BrowserSpaceBranding {
        let palette: BrowserSpaceHousePalette
        switch accent {
        case .indigo: palette = .winter
        case .orange: palette = .sun
        case .teal: palette = .meadow
        case .rose: palette = .lion
        }
        return house(palette, symbol: symbol)
    }

    /// Creates new branding from a complete preset. Decoding never applies it.
    static func house(
        _ palette: BrowserSpaceHousePalette,
        symbol: String
    ) -> BrowserSpaceBranding {
        BrowserSpaceBranding(
            colors: palette.colors,
            bannerPattern: .diagonal,
            bannerStrength: 1,
            readabilityFade: initialReadabilityFade,
            iconStyle: .layeredCrest,
            crest: palette.crest,
            hasCustomAppearance: false
        )
    }

    static func neutralImport(symbol: String) -> BrowserSpaceBranding {
        BrowserSpaceBranding(
            colors: [
                BrowserSpaceBrandColor(
                    red: 0.24,
                    green: 0.25,
                    blue: 0.27
                )
            ],
            bannerPattern: .solid,
            bannerStrength: 1,
            readabilityFade: 0.34,
            themeMode: .banner,
            showsTexture: false,
            iconStyle: .simpleSymbol,
            crest: BrowserSpaceCrest(symbol: crestSymbol(forLegacySymbol: symbol))
        )
    }

    func normalized() -> BrowserSpaceBranding {
        BrowserSpaceBranding(
            colors: colors,
            bannerPattern: bannerPattern,
            bannerStrength: bannerStrength,
            readabilityFade: readabilityFade,
            themeMode: themeMode,
            gradientAngle: gradientAngle,
            showsTexture: showsTexture,
            iconStyle: iconStyle,
            symbolColor: symbolColor,
            crest: crest,
            folderColorIntensity: folderColorIntensity,
            textColorMode: textColorMode,
            hasCustomAppearance: hasCustomAppearance
        )
    }

    func color(for role: BrowserSpaceBrandColorRole) -> BrowserSpaceBrandColor? {
        let index = role.rawValue
        return colors.indices.contains(index) ? colors[index] : nil
    }

    var backgroundColor: BrowserSpaceBrandColor {
        color(for: .background) ?? .indigo
    }

    var primaryColor: BrowserSpaceBrandColor {
        color(for: .primary) ?? backgroundColor
    }

    var resolvedSymbolColor: BrowserSpaceBrandColor {
        symbolColor ?? primaryColor
    }

    var secondaryColor: BrowserSpaceBrandColor {
        color(for: .secondary) ?? primaryColor
    }

    private static func normalizedGradientAngle(_ angle: Double) -> Double {
        guard angle.isFinite else { return 0 }
        let remainder = angle.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private static func crestSymbol(forLegacySymbol symbol: String) -> BrowserSpaceCrestSymbol {
        if symbol.contains("leaf") { return .leaf }
        if symbol.contains("book") || symbol.contains("graduation") { return .book }
        if symbol.contains("key") { return .key }
        if symbol.contains("flame") { return .flame }
        if symbol.contains("compass") || symbol.contains("location") { return .compass }
        if symbol.contains("sun") { return .sun }
        return .mountain
    }

    private enum CodingKeys: String, CodingKey {
        case colors
        case bannerPattern
        case bannerStrength
        case readabilityFade
        case keepsControlsReadable
        case themeMode
        case gradientAngle
        case showsTexture
        case iconStyle
        case symbolColor
        case crest
        case renderingVersion
        case folderColorIntensity
        case textColorMode
        case hasCustomAppearance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyReadability =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .keepsControlsReadable
            ) ?? true
        let decodedFade =
            try container.decodeIfPresent(
                Double.self,
                forKey: .readabilityFade
            ) ?? (legacyReadability ? 0.25 : 0)
        let storedStrength = try container.decode(Double.self, forKey: .bannerStrength)
        let renderingVersion =
            try container.decodeIfPresent(
                Int.self,
                forKey: .renderingVersion
            ) ?? 1
        let migratedStrength =
            renderingVersion >= Self.baselineRenderingVersion
            ? storedStrength
            : min(1, 0.72 + storedStrength * 0.28)
        self.init(
            colors: try container.decode([BrowserSpaceBrandColor].self, forKey: .colors),
            bannerPattern: container.decodeTolerantly(.bannerPattern, default: .solid),
            bannerStrength: migratedStrength,
            readabilityFade: decodedFade,
            themeMode: container.decodeTolerantly(.themeMode, default: .banner),
            gradientAngle: try container.decodeIfPresent(
                Double.self,
                forKey: .gradientAngle
            ) ?? 0,
            showsTexture: try container.decodeIfPresent(
                Bool.self,
                forKey: .showsTexture
            ) ?? false,
            iconStyle: container.decodeTolerantly(.iconStyle, default: .simpleSymbol),
            symbolColor: try container.decodeIfPresent(BrowserSpaceBrandColor.self, forKey: .symbolColor),
            crest: try container.decode(BrowserSpaceCrest.self, forKey: .crest),
            folderColorIntensity: (try? container.decodeIfPresent(Double.self, forKey: .folderColorIntensity)) ?? 0,
            textColorMode: container.decodeTolerantly(.textColorMode, default: .automatic),
            hasCustomAppearance: try container.decodeIfPresent(Bool.self, forKey: .hasCustomAppearance)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(colors, forKey: .colors)
        try container.encode(bannerPattern, forKey: .bannerPattern)
        try container.encode(bannerStrength, forKey: .bannerStrength)
        try container.encode(readabilityFade, forKey: .readabilityFade)
        try container.encode(keepsControlsReadable, forKey: .keepsControlsReadable)
        try container.encode(themeMode, forKey: .themeMode)
        try container.encode(gradientAngle, forKey: .gradientAngle)
        try container.encode(showsTexture, forKey: .showsTexture)
        try container.encode(iconStyle, forKey: .iconStyle)
        try container.encodeIfPresent(symbolColor, forKey: .symbolColor)
        try container.encode(crest, forKey: .crest)
        try container.encode(renderingVersion, forKey: .renderingVersion)
        try container.encode(normalized().folderColorIntensity, forKey: .folderColorIntensity)
        try container.encode(textColorMode, forKey: .textColorMode)
        try container.encodeIfPresent(hasCustomAppearance, forKey: .hasCustomAppearance)
    }
}
