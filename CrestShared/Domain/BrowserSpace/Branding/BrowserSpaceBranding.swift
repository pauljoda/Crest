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
    static let currentRenderingVersion = expandedChargeRenderingVersion

    var colors: [BrowserSpaceBrandColor]
    var bannerPattern: BrowserSpaceBannerPattern
    var bannerStrength: Double
    var readabilityFade: Double
    var themeMode: BrowserSpaceThemeMode
    var gradientAngle: Double
    var showsTexture: Bool
    var iconStyle: BrowserSpaceIconStyle
    var crest: BrowserSpaceCrest

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
        max(Self.baselineRenderingVersion, crest.requiredRenderingVersion)
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
        crest: BrowserSpaceCrest = BrowserSpaceCrest()
    ) {
        let normalizedColors = colors.isEmpty
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
        self.crest = crest.normalized(forColorCount: normalizedColors.count)
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
        var branding = legacy(accent: accent, symbol: symbol)
        branding.readabilityFade = initialReadabilityFade
        return branding
    }

    /// Branding for a Space that Crest itself creates, dressed in one of the
    /// shipped palettes. The palette's colors are copied in, exactly as if the
    /// reader had picked the swatch.
    static func house(
        _ palette: BrowserSpaceHousePalette,
        symbol: String
    ) -> BrowserSpaceBranding {
        BrowserSpaceBranding(
            colors: palette.colors,
            bannerPattern: .diagonal,
            bannerStrength: 1,
            readabilityFade: initialReadabilityFade,
            iconStyle: .simpleSymbol,
            crest: BrowserSpaceCrest(symbol: crestSymbol(forLegacySymbol: symbol))
        )
    }

    static func neutralImport(symbol: String) -> BrowserSpaceBranding {
        BrowserSpaceBranding(
            colors: [BrowserSpaceBrandColor(
                red: 0.24,
                green: 0.25,
                blue: 0.27
            )],
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
            crest: crest
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
        case crest
        case renderingVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyReadability = try container.decodeIfPresent(
            Bool.self,
            forKey: .keepsControlsReadable
        ) ?? true
        let decodedFade = try container.decodeIfPresent(
            Double.self,
            forKey: .readabilityFade
        ) ?? (legacyReadability ? 0.25 : 0)
        let storedStrength = try container.decode(Double.self, forKey: .bannerStrength)
        let renderingVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .renderingVersion
        ) ?? 1
        let migratedStrength = renderingVersion >= Self.baselineRenderingVersion
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
            crest: try container.decode(BrowserSpaceCrest.self, forKey: .crest)
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
        try container.encode(crest, forKey: .crest)
        try container.encode(renderingVersion, forKey: .renderingVersion)
    }
}
