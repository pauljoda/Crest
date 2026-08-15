extension BrowserSpaceForgeStep: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        case .field: "Field"
        case .pattern: "Pattern"
        case .mark: "Mark"
        case .shield: "Shield"
        case .division: "Field Division"
        case .ordinary: "Ordinary"
        case .charge: "Charge"
        case .trim: "Trim"
        }
    }
}
