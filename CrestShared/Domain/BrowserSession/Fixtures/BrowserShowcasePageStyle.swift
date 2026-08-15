enum BrowserShowcasePageStyle {
    case work
    case personal

    var background: String { self == .work ? "#f3efe5" : "#eef2e8" }
    var ink: String { self == .work ? "#15233b" : "#20372d" }
    var accent: String { self == .work ? "#315f98" : "#6d8d68" }
    var warm: String { self == .work ? "#d6ab4e" : "#d7684f" }
    var kicker: String { self == .work ? "NORTHSTAR STUDIO" : "FIELD NOTES" }

    var headline: String {
        self == .work
            ? "Make space for the work that matters."
            : "A slower Saturday starts here."
    }

    var summary: String {
        self == .work
            ? "A calm command center for launches, decisions, and the people moving them forward."
            : "Plans for good food, open roads, a little dirt under your nails, and time to read."
    }

    var cards: [(String, String)] {
        self == .work
            ? [
                ("Today", "Three decisions, one clear priority"),
                ("Atlas", "Research is ready for review"),
                ("Launch", "Milestone check-in at 2:30"),
                ("Notes", "Seven ideas worth keeping"),
            ]
            : [
                ("Weekend", "Market, trail, then nowhere to be"),
                ("Trips", "Cabin map and quiet roads"),
                ("Garden", "What to plant before the rain"),
                ("Reading", "Four essays for Sunday morning"),
            ]
    }
}
