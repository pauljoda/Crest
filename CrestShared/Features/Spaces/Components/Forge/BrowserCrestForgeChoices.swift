import Foundation

// The parts More Customization offers a crest: the ones that read at a
// sidebar's size and that the starter crests wear, with no fine tuning.
// A crest that already wears another keeps it.

extension CrestBackplate {
    static let offered: [CrestBackplate] = [
        .shield, .frenchShield, .circle, .seal, .hexagon, .octagon, .diamond, .banner,
    ]
}

extension CrestFieldDivision {
    static let offered: [CrestFieldDivision] = [.plain, .perPale, .perFess, .perBend, .perChevron, .quarterly, .barry]
}

extension CrestOrdinary {
    static let offered: [CrestOrdinary] = [.none, .pale, .fess, .bend, .chevron, .cross, .saltire, .chief]
}

extension CrestTrim {
    static let offered: [CrestTrim] = [.none, .line, .doubleLine, .laurel, .sunburst, .doubleRing, .beaded]
}

extension CrestChargeLayout {
    static let offered: [CrestChargeLayout] = [.single, .paired, .trio]
}

/// How a crest is finished: its surface and the shadow under it, chosen
/// together.
struct BrowserCrestFinishChoice: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let flat = BrowserCrestFinishChoice(name: "flat", title: "Flat", finish: .flat, depth: .none)
    static let shadow = BrowserCrestFinishChoice(name: "shadow", title: "Shadow", finish: .flat, depth: .soft)
    static let sheen = BrowserCrestFinishChoice(name: "sheen", title: "Sheen", finish: .sheen, depth: .lifted)
    static let embossed = BrowserCrestFinishChoice(name: "embossed", title: "Embossed", finish: .embossed, depth: .soft)

    static let all: [BrowserCrestFinishChoice] = [flat, shadow, sheen, embossed]

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    let finish: CrestFinish
    let depth: CrestDepth

    var id: String { name }

    // MARK: - Initializers

    private init(name: String, title: LocalizedStringResource, finish: CrestFinish, depth: CrestDepth) {
        self.name = name
        self.title = title
        self.finish = finish
        self.depth = depth
    }

    // MARK: - Functions

    /// Whether `crest` is finished this way: its surface, and for a flat
    /// one, whether it casts a shadow.
    func isWorn(by crest: SpaceCrest) -> Bool {
        guard crest.finish == finish else { return false }
        return finish != .flat || (crest.depth == .none) == (depth == .none)
    }

    /// `crest` finished this way.
    func applying(to crest: SpaceCrest) -> SpaceCrest {
        var finished = crest
        finished.finish = finish
        finished.depth = depth
        return finished
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserCrestFinishChoice, rhs: BrowserCrestFinishChoice) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
