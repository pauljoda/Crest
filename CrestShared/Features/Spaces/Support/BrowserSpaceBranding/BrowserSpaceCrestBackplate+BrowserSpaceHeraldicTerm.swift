extension BrowserSpaceCrestBackplate: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        case .none: "None"
        case .circle: "Round"
        case .shield: "Shield"
        case .diamond: "Lozenge"
        case .seal: "Seal"
        case .hexagon: "Hexagon"
        }
    }

    var systemImage: String? {
        switch self {
        case .none: nil
        case .circle: "circle.fill"
        case .shield: "shield.fill"
        case .diamond: "diamond.fill"
        case .seal: "seal.fill"
        case .hexagon: "hexagon.fill"
        }
    }

    var outlineSystemImage: String? {
        switch self {
        case .none: nil
        case .circle: "circle"
        case .shield: "shield"
        case .diamond: "diamond"
        case .seal: "seal"
        case .hexagon: "hexagon"
        }
    }
}
