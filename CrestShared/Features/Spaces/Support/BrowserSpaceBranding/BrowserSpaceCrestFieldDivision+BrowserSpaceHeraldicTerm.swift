extension BrowserSpaceCrestFieldDivision: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        // Kept to one word: these are gallery card captions under a 46pt crest,
        // and the card already shows what the division does.
        case .plain: "Plain"
        case .perPale: "Vertical"
        case .perFess: "Horizontal"
        case .perBend: "Diagonal"
        case .perChevron: "Chevron"
        case .quarterly: "Quartered"
        }
    }
}
