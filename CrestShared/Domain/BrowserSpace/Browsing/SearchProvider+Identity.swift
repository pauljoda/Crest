import Foundation

extension SearchProvider: Identifiable {
    // MARK: - Variables

    var id: String {
        name
    }

    /// Whether a person added the provider rather than Crest shipping it.
    var isCustom: Bool {
        customID != nil
    }

    /// The website whose icon stands for a provider without a logo.
    var iconPageURL: URL? {
        guard logo == nil, !site.isEmpty else { return nil }
        return URL(string: "https://\(site)/")
    }

    /// What the palette's row for the provider says, as "Search Google" or "Ask Claude".
    var actionTitle: String {
        kind == .assistant
            ? String(localized: "Ask \(title)", comment: "A palette row that asks an AI assistant.")
            : String(localized: "Search \(title)", comment: "A palette row that searches a search engine or website.")
    }
}

extension SearchProvider: Hashable {
    // MARK: - Actions - Identity

    /// Providers that are equal share a name, so the name alone hashes them.
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
