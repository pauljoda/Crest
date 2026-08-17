import Foundation

enum BrowserShowcaseSessionFactory {
    static func make() -> BrowserSession {
        let work = makeWorkSpace()
        let personal = makePersonalSpace()
        return BrowserSession(spaces: [work, personal], selectedSpaceID: work.id)
    }

    private static func makeWorkSpace() -> BrowserSpace {
        let folder = SavedFolder(title: "Launch Atlas", symbol: "folder.fill")
        let splitGroupID = SplitGroupID()
        let secondSplitGroupID = SplitGroupID()
        let tabs = [
            tab("Brief", page(.work, title: "Brief", activeCard: 0), "🧭", .pinned),
            tab("Projects", page(.work, title: "Projects", activeCard: 1), "📐", .pinned),
            tab("Calendar", page(.work, title: "Calendar", activeCard: 2), "📅", .pinned),
            tab("Notes", page(.work, title: "Notes", activeCard: 3), "✍️", .pinned),
            tab("Audience research", page(.work, title: "Audience research", activeCard: 1), "🔬", .saved, folder.id),
            tab("Launch plan", page(.work, title: "Launch plan", activeCard: 2), "🚩", .saved, folder.id),
            tab("Design review", page(.work, title: "Design review", activeCard: 3), "🎨", .saved, folder.id),
            tab(
                "Monday overview",
                page(.work, title: "Monday overview", activeCard: 0),
                "✨",
                .current,
                splitGroupID: splitGroupID
            ),
            tab(
                "Launch notes",
                page(.work, title: "Launch notes", activeCard: 3),
                "🗒️",
                .current,
                splitGroupID: splitGroupID
            ),
            tab(
                "Decision log",
                page(.work, title: "Decision log", activeCard: 1),
                "🧠",
                .current,
                splitGroupID: secondSplitGroupID
            ),
            tab(
                "Launch checklist",
                page(.work, title: "Launch checklist", activeCard: 2),
                "✅",
                .current,
                splitGroupID: secondSplitGroupID
            ),
        ]
        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "hammer.fill",
            accent: .indigo,
            branding: BrowserSpaceBranding(
                colors: [.ink, .ocean, .gold],
                bannerPattern: .diagonal,
                bannerStrength: 1,
                readabilityFade: 0.42,
                themeMode: .banner,
                gradientAngle: 132,
                showsTexture: true,
                iconStyle: .layeredCrest,
                crest: BrowserSpaceCrest(
                    backplate: .shield,
                    fieldDivision: .perBend,
                    ordinary: .bordure,
                    trim: .laurel,
                    symbol: .hammer,
                    chargeLayout: .single,
                    backplateColorIndex: 0,
                    secondaryFieldColorIndex: 1,
                    ordinaryColorIndex: 2,
                    trimColorIndex: 2,
                    symbolColorIndex: 2
                )
            ),
            folders: [folder],
            tabs: tabs,
            selectedTabID: tabs.last?.id
        )
    }

    private static func makePersonalSpace() -> BrowserSpace {
        let folder = SavedFolder(title: "Weekend Plans", symbol: "folder.fill")
        let tabs = [
            tab("Home", page(.personal, title: "Home", activeCard: 0), "🏡", .pinned),
            tab("Trips", page(.personal, title: "Trips", activeCard: 1), "🗺️", .pinned),
            tab("Recipes", page(.personal, title: "Recipes", activeCard: 2), "🍲", .pinned),
            tab("Reading", page(.personal, title: "Reading", activeCard: 3), "📚", .pinned),
            tab("Cabin ideas", page(.personal, title: "Cabin ideas", activeCard: 1), "🏔️", .saved, folder.id),
            tab("Garden notes", page(.personal, title: "Garden notes", activeCard: 2), "🌱", .saved, folder.id),
            tab("Sunday reading", page(.personal, title: "Sunday reading", activeCard: 3), "📖", .saved, folder.id),
            tab("A slower Saturday", page(.personal, title: "A slower Saturday", activeCard: 0), "☀️", .current),
        ]
        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Personal",
            symbol: "leaf.fill",
            accent: .teal,
            branding: BrowserSpaceBranding(
                colors: [.sage, .sand, .ember],
                bannerPattern: .chevron,
                bannerStrength: 1,
                readabilityFade: 0.38,
                themeMode: .banner,
                gradientAngle: 28,
                showsTexture: true,
                iconStyle: .layeredCrest,
                crest: BrowserSpaceCrest(
                    backplate: .seal,
                    fieldDivision: .perPale,
                    ordinary: .fess,
                    trim: .sunburst,
                    symbol: .leaf,
                    chargeLayout: .single,
                    backplateColorIndex: 0,
                    secondaryFieldColorIndex: 1,
                    ordinaryColorIndex: 2,
                    trimColorIndex: 1,
                    symbolColorIndex: 1
                )
            ),
            folders: [folder],
            tabs: tabs,
            selectedTabID: tabs.last?.id
        )
    }

    private static func page(
        _ style: BrowserShowcasePageStyle,
        title: String,
        activeCard: Int
    ) -> URL {
        let cardMarkup = style.cards.enumerated().map { index, card in
            """
            <article class="card \(index == activeCard ? "active" : "")">
              <span>0\(index + 1)</span><h2>\(card.0)</h2><p>\(card.1)</p>
            </article>
            """
        }.joined()
        let html = """
            <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>\(title)</title><style>
            *{box-sizing:border-box}body{margin:0;padding:clamp(32px,6vw,84px);color:\(style.ink);background:\(style.background);font-family:-apple-system,BlinkMacSystemFont,sans-serif}main{max-width:1100px;margin:auto}.kicker{font-size:11px;font-weight:800;letter-spacing:.2em}.hero{display:grid;grid-template-columns:1.2fr .8fr;gap:40px;align-items:end;margin:8vh 0 7vh}.hero h1{margin:0;font:500 clamp(52px,8vw,100px)/.88 ui-serif,Georgia,serif;letter-spacing:-.055em}.hero p{max-width:420px;margin:0 0 8px;font-size:18px;line-height:1.55;color:color-mix(in srgb,\(style.ink) 65%,transparent)}.rule{height:10px;background:linear-gradient(90deg,\(style.accent) 0 56%,\(style.warm) 56%)}.grid{display:grid;grid-template-columns:repeat(4,1fr);border-top:1px solid color-mix(in srgb,\(style.ink) 20%,transparent);border-left:1px solid color-mix(in srgb,\(style.ink) 20%,transparent)}.card{min-height:185px;padding:24px;border-right:1px solid color-mix(in srgb,\(style.ink) 20%,transparent);border-bottom:1px solid color-mix(in srgb,\(style.ink) 20%,transparent)}.card.active{color:white;background:\(style.accent)}.card span{font-size:10px;letter-spacing:.12em}.card h2{margin:55px 0 8px;font:500 27px/1 ui-serif,Georgia,serif}.card p{margin:0;font-size:12px;line-height:1.45;opacity:.68}@media(max-width:700px){.hero{grid-template-columns:1fr;margin-top:5vh}.hero h1{font-size:54px}.grid{grid-template-columns:1fr 1fr}.card{min-height:150px}.card h2{margin-top:30px}}
            </style></head><body><main><div class="kicker">\(style.kicker) · \(title.uppercased())</div><section class="hero"><h1>\(style.headline)</h1><p>\(style.summary)</p></section><div class="rule"></div><section class="grid">\(cardMarkup)</section></main></body></html>
            """
        guard
            let encoded = html.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics
            ), let url = URL(string: "data:text/html;charset=utf-8,\(encoded)")
        else {
            return URL(fileURLWithPath: "/")
        }
        return url
    }

    private static func tab(
        _ title: String,
        _ url: URL,
        _ symbol: String,
        _ placement: TabPlacement,
        _ folderID: FolderID? = nil,
        splitGroupID: SplitGroupID? = nil
    ) -> BrowserTab {
        BrowserTab(
            title: title,
            url: url,
            symbol: BrowserTab.symbol(forEmoji: symbol),
            iconMode: .emoji,
            placement: placement,
            folderID: folderID,
            splitGroupID: splitGroupID,
            lastActivatedAt: .now
        )
    }
}

// MARK: - Page Style

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

// MARK: - Browser Session

extension BrowserSession {
    static let showcase: BrowserSession = BrowserShowcaseSessionFactory.make()
}
