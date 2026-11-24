import SwiftUI

/// What the selected tab and the selected pin are drawn on: a sheet of
/// Crest's white paper, as translucent as the person chooses, or a layer of
/// the device's material in its material color.
///
/// One choice for the whole device, made in Look and Feel beside the other
/// tab choices and stored by name in ``BrowserTabAppearance``.
struct BrowserSelectedTabStyle: Hashable, Sendable, Identifiable {
    // MARK: - Static Variables

    /// A sheet of Crest's white paper with ink text, laid over a pin's site
    /// color.
    static let white = BrowserSelectedTabStyle(name: "white", title: "White", liesOnPaper: true)
    /// A layer of the device's material in its material color, with text in
    /// the scheme that color gives it, as the pins and the address field are.
    static let material = BrowserSelectedTabStyle(name: "material", title: "Material", liesOnPaper: false)
    static let all = [white, material]
    static let standard = white

    // MARK: - Variables

    /// The persisted spelling.
    let name: String
    let title: LocalizedStringResource
    /// Whether the selection is a sheet of paper, whose opacity the person
    /// chooses, rather than the device's material, which sets its own.
    let liesOnPaper: Bool
    var id: String { name }
    /// The color a selection's text is drawn in: ink on paper, else the
    /// label color of the material's scheme.
    var foreground: Color { liesOnPaper ? CrestBrandTheme.textDisplay : .primary }

    // MARK: - Initializers

    private init(name: String, title: LocalizedStringResource, liesOnPaper: Bool) {
        self.name = name
        self.title = title
        self.liesOnPaper = liesOnPaper
    }

    // MARK: - Actions - Lookup

    static func named(_ name: String?) -> BrowserSelectedTabStyle? {
        all.first { $0.name == name }
    }

    // MARK: - Actions - Drawing

    /// The sheet a selection in this style lies on, `opacity` opaque over
    /// `ground`, or nil where it lies on the device's material.
    func paper(opacity: Double, ground: Color? = nil) -> CrestPaperSheet? {
        liesOnPaper ? CrestPaperSheet(opacity: opacity, ground: ground) : nil
    }

    /// The scheme a selection's text reads in: light on paper, which is
    /// always light, else `materialScheme`, the one the device's material
    /// color gives the material.
    func contentScheme(onMaterial materialScheme: ColorScheme) -> ColorScheme {
        liesOnPaper ? .light : materialScheme
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSelectedTabStyle, rhs: BrowserSelectedTabStyle) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

// MARK: - Codable

extension BrowserSelectedTabStyle: Codable {
    /// Decodes a stored spelling, failing on one this build does not know.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let style = Self.named(name) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "No selected tab style is named \(name).")
        }
        self = style
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}
