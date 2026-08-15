extension BrowserSpaceCrestTrim: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        case .none: "None"
        case .shield: "Shield"
        case .laurel: "Laurel"
        case .sunburst: "Sunburst"
        case .doubleRing: "Double Ring"
        case .seal: "Seal"
        }
    }
}
