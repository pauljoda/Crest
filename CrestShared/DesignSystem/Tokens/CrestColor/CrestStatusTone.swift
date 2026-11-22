import SwiftUI

/// How a status reads at a glance: settled, under way, needing the person, or
/// in trouble. A status that is none of these has no tone and stays in its
/// view's quiet style. Objects that report a status carry its tone, so views
/// draw the same status in the same colour everywhere. Each tone is the
/// colour of the core's tone of the same name.
struct CrestStatusTone: Hashable, Sendable {
    // MARK: - Static Variables

    static let success = CrestStatusTone(name: "success", color: CrestColor.success)
    static let warning = CrestStatusTone(name: "warning", color: CrestColor.warning)
    static let danger = CrestStatusTone(name: "danger", color: CrestColor.danger)
    /// Something under way, or done without the person, in Crest blue.
    static let info = CrestStatusTone(name: "info", color: CrestBrandTheme.accent)

    static let all = [success, warning, danger, info]

    // MARK: - Variables

    let name: String
    /// The colour the status's words, glyph or badge draw in.
    let color: Color

    // MARK: - Initializers

    private init(name: String, color: Color) {
        self.name = name
        self.color = color
    }

    /// The tone the core gives a status, or nil for a status it gives none,
    /// or one this build has no colour for.
    init?(_ tone: StatusTone?) {
        guard let tone, let shown = Self.all.first(where: { $0.name == tone.name }) else { return nil }
        self = shown
    }

    // MARK: - Actions - Identity

    static func == (lhs: CrestStatusTone, rhs: CrestStatusTone) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
