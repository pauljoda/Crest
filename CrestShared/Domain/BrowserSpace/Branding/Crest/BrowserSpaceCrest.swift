import Foundation

/// The composition of a Space's crest.
///
/// Stored compositions keep their semantics while path geometry replaces the old
/// glyph masks. New controls have neutral defaults; only Studio features advance
/// the rendering vocabulary.
struct BrowserSpaceCrest: Codable, Equatable, Sendable {
    // Composition
    var backplate: BrowserSpaceCrestBackplate
    var fieldDivision: BrowserSpaceCrestFieldDivision
    var ordinary: BrowserSpaceCrestOrdinary
    var trim: BrowserSpaceCrestTrim
    var symbol: BrowserSpaceCrestSymbol
    var chargeLayout: BrowserSpaceCrestChargeLayout

    // Layer colors: indices into ``palette`` when set, else into the Space's colors.
    var backplateColorIndex: Int
    var secondaryFieldColorIndex: Int
    var ordinaryColorIndex: Int
    var trimColorIndex: Int
    var symbolColorIndex: Int
    var edgeColorIndex: Int

    // Studio parameters
    /// The crest's own tinctures. Nil follows the Space palette as it changes.
    var palette: [BrowserSpaceBrandColor]?
    /// A figure that is not one of the heraldic set. Nil draws ``symbol``.
    var charge: BrowserSpaceCrestCharge?
    var plateScale: Double
    var edgeWidth: Double
    var divisionCount: Int
    var finish: BrowserSpaceCrestFinish
    var ordinaryWidth: Double
    var trimWeight: Double
    var trimDetail: Int
    var chargeScale: Double
    var chargeOffset: Double
    var chargeWeight: BrowserSpaceCrestChargeWeight
    var startingPresetID: String?
    var sheenAngle: Double
    var sealTeeth: Int
    var showsOutline: Bool
    var depth: BrowserSpaceCrestDepth

    static let maximumPaletteCount = 4
    static let plateScaleRange = 0.7...1.15
    static let edgeWidthRange = 0.0...1.0
    static let divisionCountRange = 2...8
    static let ordinaryWidthRange = 0.5...1.6
    static let trimWeightRange = 0.5...2.0
    static let trimDetailRange = 6...24
    static let chargeScaleRange = 0.6...1.5
    static let chargeOffsetRange = -0.2...0.2

    static let defaultDivisionCount = 4
    static let defaultTrimDetail = 12

    init(
        backplate: BrowserSpaceCrestBackplate = .shield,
        fieldDivision: BrowserSpaceCrestFieldDivision = .plain,
        ordinary: BrowserSpaceCrestOrdinary = .none,
        trim: BrowserSpaceCrestTrim = .none,
        symbol: BrowserSpaceCrestSymbol = .mountain,
        chargeLayout: BrowserSpaceCrestChargeLayout = .single,
        backplateColorIndex: Int = BrowserSpaceBrandColorRole.primary.rawValue,
        secondaryFieldColorIndex: Int = 1,
        ordinaryColorIndex: Int = 2,
        trimColorIndex: Int = 1,
        symbolColorIndex: Int = 2,
        edgeColorIndex: Int? = nil,
        palette: [BrowserSpaceBrandColor]? = nil,
        charge: BrowserSpaceCrestCharge? = nil,
        plateScale: Double = 1,
        edgeWidth: Double = 0,
        divisionCount: Int = defaultDivisionCount,
        finish: BrowserSpaceCrestFinish = .flat,
        ordinaryWidth: Double = 1,
        trimWeight: Double = 1,
        trimDetail: Int = defaultTrimDetail,
        chargeScale: Double = 1,
        chargeOffset: Double = 0,
        chargeWeight: BrowserSpaceCrestChargeWeight = .bold,
        startingPresetID: String? = nil,
        sheenAngle: Double = 45,
        sealTeeth: Int = 12,
        showsOutline: Bool = false,
        depth: BrowserSpaceCrestDepth = .none
    ) {
        self.backplate = backplate
        self.fieldDivision = fieldDivision
        self.ordinary = ordinary
        self.trim = trim
        self.symbol = symbol
        self.chargeLayout = chargeLayout
        self.backplateColorIndex = backplateColorIndex
        self.secondaryFieldColorIndex = secondaryFieldColorIndex
        self.ordinaryColorIndex = ordinaryColorIndex
        self.trimColorIndex = trimColorIndex
        self.symbolColorIndex = symbolColorIndex
        self.edgeColorIndex = edgeColorIndex ?? trimColorIndex
        self.palette = palette
        self.charge = charge
        self.plateScale = plateScale
        self.edgeWidth = edgeWidth
        self.divisionCount = divisionCount
        self.finish = finish
        self.ordinaryWidth = ordinaryWidth
        self.trimWeight = trimWeight
        self.trimDetail = trimDetail
        self.chargeScale = chargeScale
        self.chargeOffset = chargeOffset
        self.chargeWeight = chargeWeight
        self.startingPresetID = startingPresetID
        self.sheenAngle = sheenAngle
        self.sealTeeth = sealTeeth
        self.showsOutline = showsOutline
        self.depth = depth
    }

    /// The figure this crest draws: a custom charge when one was chosen, else
    /// the heraldic symbol.
    var resolvedCharge: BrowserSpaceCrestCharge {
        charge ?? .heraldic(symbol)
    }

    /// Whether the crest draws with its own tinctures rather than the Space's.
    var usesOwnPalette: Bool { palette != nil }

    /// The colors this crest's layer indices point into.
    func layerColors(spaceColors: [BrowserSpaceBrandColor]) -> [BrowserSpaceBrandColor] {
        if let palette, !palette.isEmpty { return palette }
        return spaceColors.isEmpty ? [.indigo] : spaceColors
    }

    /// Clamps every index and parameter into range. Layer indices point into
    /// the crest's own palette when it has one, else into the Space's colors.
    func normalized(forColorCount spaceColorCount: Int) -> BrowserSpaceCrest {
        let palette = palette.map { Array($0.prefix(Self.maximumPaletteCount)) }.flatMap { $0.isEmpty ? nil : $0 }
        let upperBound = max(palette?.count ?? spaceColorCount, 1)
        func validated(_ index: Int) -> Int {
            (0..<upperBound).contains(index) ? index : 0
        }
        func clamped(_ value: Double, _ range: ClosedRange<Double>, default fallback: Double) -> Double {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        return BrowserSpaceCrest(
            backplate: backplate,
            fieldDivision: fieldDivision,
            ordinary: ordinary,
            trim: trim,
            symbol: symbol,
            chargeLayout: chargeLayout,
            backplateColorIndex: validated(backplateColorIndex),
            secondaryFieldColorIndex: validated(secondaryFieldColorIndex),
            ordinaryColorIndex: validated(ordinaryColorIndex),
            trimColorIndex: validated(trimColorIndex),
            symbolColorIndex: validated(symbolColorIndex),
            edgeColorIndex: validated(edgeColorIndex),
            palette: palette,
            charge: charge.map { $0.normalized }.flatMap { $0.isHeraldic && $0 == .heraldic(symbol) ? nil : $0 },
            plateScale: clamped(plateScale, Self.plateScaleRange, default: 1),
            edgeWidth: clamped(edgeWidth, Self.edgeWidthRange, default: 0),
            divisionCount: min(
                max(divisionCount, Self.divisionCountRange.lowerBound), Self.divisionCountRange.upperBound),
            finish: finish,
            ordinaryWidth: clamped(ordinaryWidth, Self.ordinaryWidthRange, default: 1),
            trimWeight: clamped(trimWeight, Self.trimWeightRange, default: 1),
            trimDetail: min(max(trimDetail, Self.trimDetailRange.lowerBound), Self.trimDetailRange.upperBound),
            chargeScale: clamped(chargeScale, Self.chargeScaleRange, default: 1),
            chargeOffset: clamped(chargeOffset, Self.chargeOffsetRange, default: 0),
            chargeWeight: chargeWeight,
            startingPresetID: startingPresetID,
            sheenAngle: clamped(sheenAngle, 0...360, default: 45),
            sealTeeth: min(max(sealTeeth, 6), 24),
            showsOutline: showsOutline,
            depth: depth
        )
    }

    /// Whether the composition uses a Studio rendering control.
    var usesStudioParameters: Bool {
        palette != nil || charge != nil || plateScale != 1 || edgeWidth != 0
            || (fieldDivision.isCounted && divisionCount != Self.defaultDivisionCount)
            || finish != .flat || sheenAngle != 45 || showsOutline || (backplate == .seal && sealTeeth != 12)
            || ordinaryWidth != 1 || trimWeight != 1
            || (trim.isCounted && trimDetail != Self.defaultTrimDetail)
            || chargeScale != 1 || chargeOffset != 0 || chargeWeight != .bold || depth != .none
    }

    /// The rendering vocabulary this crest needs in order to draw as composed.
    var requiredRenderingVersion: Int {
        max(
            BrowserSpaceBranding.baselineRenderingVersion,
            symbol.introducedInRenderingVersion,
            backplate.introducedInRenderingVersion,
            fieldDivision.introducedInRenderingVersion,
            ordinary.introducedInRenderingVersion,
            trim.introducedInRenderingVersion,
            chargeLayout.introducedInRenderingVersion,
            usesStudioParameters ? BrowserSpaceBranding.crestStudioRenderingVersion : 0
        )
    }

    private enum CodingKeys: String, CodingKey {
        case backplate
        case fieldDivision
        case ordinary
        case trim
        case symbol
        case chargeLayout
        case backplateColorIndex
        case secondaryFieldColorIndex
        case ordinaryColorIndex
        case trimColorIndex
        case symbolColorIndex
        case edgeColorIndex
        case palette
        case charge
        case plateScale
        case edgeWidth
        case divisionCount
        case finish
        case ordinaryWidth
        case trimWeight
        case trimDetail
        case chargeScale
        case chargeOffset
        case chargeWeight
        case startingPresetID
        case sheenAngle
        case sealTeeth
        case showsOutline
        case depth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func index(_ key: CodingKeys, default fallback: Int) -> Int {
            (try? container.decodeIfPresent(Int.self, forKey: key)) ?? fallback
        }
        func number(_ key: CodingKeys, default fallback: Double) -> Double {
            (try? container.decodeIfPresent(Double.self, forKey: key)) ?? fallback
        }
        self.init(
            backplate: container.decodeTolerantly(.backplate, default: .shield),
            fieldDivision: container.decodeTolerantly(.fieldDivision, default: .plain),
            ordinary: container.decodeTolerantly(.ordinary, default: .none),
            trim: container.decodeTolerantly(.trim, default: .none),
            symbol: container.decodeTolerantly(.symbol, default: BrowserSpaceCrestSymbol.fallback),
            chargeLayout: container.decodeTolerantly(.chargeLayout, default: .single),
            backplateColorIndex: index(.backplateColorIndex, default: 0),
            secondaryFieldColorIndex: index(.secondaryFieldColorIndex, default: 0),
            ordinaryColorIndex: index(.ordinaryColorIndex, default: 0),
            trimColorIndex: index(.trimColorIndex, default: 0),
            symbolColorIndex: index(.symbolColorIndex, default: 0),
            edgeColorIndex: index(.edgeColorIndex, default: index(.trimColorIndex, default: 0)),
            palette: try? container.decodeIfPresent([BrowserSpaceBrandColor].self, forKey: .palette),
            charge: try? container.decodeIfPresent(BrowserSpaceCrestCharge.self, forKey: .charge),
            plateScale: number(.plateScale, default: 1),
            edgeWidth: number(.edgeWidth, default: 0),
            divisionCount: index(.divisionCount, default: Self.defaultDivisionCount),
            finish: container.decodeTolerantly(.finish, default: .flat),
            ordinaryWidth: number(.ordinaryWidth, default: 1),
            trimWeight: number(.trimWeight, default: 1),
            trimDetail: index(.trimDetail, default: Self.defaultTrimDetail),
            chargeScale: number(.chargeScale, default: 1),
            chargeOffset: number(.chargeOffset, default: 0),
            chargeWeight: container.decodeTolerantly(.chargeWeight, default: .bold),
            startingPresetID: try? container.decodeIfPresent(String.self, forKey: .startingPresetID),
            sheenAngle: number(.sheenAngle, default: 45),
            sealTeeth: index(.sealTeeth, default: 12),
            showsOutline: (try? container.decodeIfPresent(Bool.self, forKey: .showsOutline)) ?? false,
            depth: container.decodeTolerantly(.depth, default: .none)
        )
    }

    /// Studio fields are written only when they carry something, so a crest
    /// that never used the studio encodes exactly the keys it always did.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(backplate, forKey: .backplate)
        try container.encode(fieldDivision, forKey: .fieldDivision)
        try container.encode(ordinary, forKey: .ordinary)
        try container.encode(trim, forKey: .trim)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(chargeLayout, forKey: .chargeLayout)
        try container.encode(backplateColorIndex, forKey: .backplateColorIndex)
        try container.encode(secondaryFieldColorIndex, forKey: .secondaryFieldColorIndex)
        try container.encode(ordinaryColorIndex, forKey: .ordinaryColorIndex)
        try container.encode(trimColorIndex, forKey: .trimColorIndex)
        try container.encode(symbolColorIndex, forKey: .symbolColorIndex)
        try container.encodeIfPresent(startingPresetID, forKey: .startingPresetID)
        guard usesStudioParameters || edgeColorIndex != trimColorIndex else { return }
        try container.encode(edgeColorIndex, forKey: .edgeColorIndex)
        try container.encodeIfPresent(palette, forKey: .palette)
        try container.encodeIfPresent(charge, forKey: .charge)
        try container.encode(plateScale, forKey: .plateScale)
        try container.encode(edgeWidth, forKey: .edgeWidth)
        try container.encode(divisionCount, forKey: .divisionCount)
        try container.encode(finish, forKey: .finish)
        try container.encode(ordinaryWidth, forKey: .ordinaryWidth)
        try container.encode(trimWeight, forKey: .trimWeight)
        try container.encode(trimDetail, forKey: .trimDetail)
        try container.encode(chargeScale, forKey: .chargeScale)
        try container.encode(chargeOffset, forKey: .chargeOffset)
        try container.encode(chargeWeight, forKey: .chargeWeight)
        try container.encode(sheenAngle, forKey: .sheenAngle)
        try container.encode(sealTeeth, forKey: .sealTeeth)
        try container.encode(showsOutline, forKey: .showsOutline)
        try container.encode(depth, forKey: .depth)
    }
}
