extension BrowserSpaceBannerPattern: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        case .solid: "Solid"
        case .split: "Split"
        case .bands: "Bands"
        case .diagonal: "Diagonal"
        case .chevron: "Chevron"
        case .quartered: "Quartered"
        }
    }
}
