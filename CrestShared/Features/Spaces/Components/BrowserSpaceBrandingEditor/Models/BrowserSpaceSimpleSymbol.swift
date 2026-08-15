enum BrowserSpaceSimpleSymbol: String, CaseIterable, Identifiable, Sendable {
    case work = "briefcase.fill"
    case personal = "person.fill"
    case home = "house.fill"
    case study = "graduationcap.fill"
    case creative = "paintbrush.fill"
    case games = "gamecontroller.fill"
    case travel = "airplane"
    case grid = "square.grid.2x2"

    var id: String { rawValue }
}
