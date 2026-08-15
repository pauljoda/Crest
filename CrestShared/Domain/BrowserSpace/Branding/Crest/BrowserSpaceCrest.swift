import Foundation

struct BrowserSpaceCrest: Codable, Equatable, Sendable {
    var backplate: BrowserSpaceCrestBackplate
    var fieldDivision: BrowserSpaceCrestFieldDivision
    var ordinary: BrowserSpaceCrestOrdinary
    var trim: BrowserSpaceCrestTrim
    var symbol: BrowserSpaceCrestSymbol
    var chargeLayout: BrowserSpaceCrestChargeLayout
    var backplateColorIndex: Int
    var secondaryFieldColorIndex: Int
    var ordinaryColorIndex: Int
    var trimColorIndex: Int
    var symbolColorIndex: Int

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
        symbolColorIndex: Int = 2
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
    }

    func normalized(forColorCount colorCount: Int) -> BrowserSpaceCrest {
        let upperBound = max(colorCount, 1)
        func validated(_ index: Int) -> Int {
            (0..<upperBound).contains(index) ? index : 0
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
            symbolColorIndex: validated(symbolColorIndex)
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
    }

    /// The rendering vocabulary this crest needs in order to draw as composed.
    var requiredRenderingVersion: Int {
        max(
            BrowserSpaceBranding.baselineRenderingVersion,
            symbol.introducedInRenderingVersion
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            backplate: container.decodeTolerantly(.backplate, default: .shield),
            fieldDivision: container.decodeTolerantly(.fieldDivision, default: .plain),
            ordinary: container.decodeTolerantly(.ordinary, default: .none),
            trim: container.decodeTolerantly(.trim, default: .none),
            symbol: container.decodeTolerantly(
                .symbol,
                default: BrowserSpaceCrestSymbol.fallback
            ),
            chargeLayout: container.decodeTolerantly(.chargeLayout, default: .single),
            backplateColorIndex: try container.decodeIfPresent(
                Int.self,
                forKey: .backplateColorIndex
            ) ?? 0,
            secondaryFieldColorIndex: try container.decodeIfPresent(
                Int.self,
                forKey: .secondaryFieldColorIndex
            ) ?? 0,
            ordinaryColorIndex: try container.decodeIfPresent(
                Int.self,
                forKey: .ordinaryColorIndex
            ) ?? 0,
            trimColorIndex: try container.decodeIfPresent(
                Int.self,
                forKey: .trimColorIndex
            ) ?? 0,
            symbolColorIndex: try container.decodeIfPresent(
                Int.self,
                forKey: .symbolColorIndex
            ) ?? 0
        )
    }
}
