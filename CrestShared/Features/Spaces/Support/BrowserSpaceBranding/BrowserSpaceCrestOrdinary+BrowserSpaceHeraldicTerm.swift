extension BrowserSpaceCrestOrdinary: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        case .none: "None"
        case .pale: "Pale"
        case .fess: "Fess"
        case .bend: "Bend"
        case .chevron: "Chevron"
        case .cross: "Cross"
        case .saltire: "Saltire"
        case .chief: "Chief"
        case .bordure: "Bordure"
        }
    }
}
