extension BrowserSpaceCrestChargeLayout: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        case .single: "One"
        case .paired: "Two"
        case .trio: "Three"
        }
    }
}
