import Foundation

extension AgentToolDefinition {
    // MARK: - Static Variables

    static let openPrivateWindow = Self(
        name: "open_private_window", title: "Open a Private Window",
        description:
            "Opens a Private Window at the person's request, optionally at an http or https address. Returns only a window receipt; private tabs and Spaces remain inaccessible to every tool.",
        arguments: [.string("url", "The http or https address to open.", required: false)],
        readOnly: false, destructive: false, idempotent: false, openWorld: true)
}

extension AgentToolDefinition {
    static let searchHistory = Self(
        name: "search_history", title: "Search history",
        description:
            "Searches live browsing history in allowed, unlocked Spaces. Searches before limiting the globally newest visits; private history is never included.",
        arguments: [
            .string("query", "Words that must all appear in the title or address.", required: false),
            .number("limit", "Maximum visits, from 1 to 1000. Defaults to 25."),
            .string("domain", "Only this hostname and its subdomains.", required: false),
        ], readOnly: true, destructive: false, idempotent: true, openWorld: false)
    static let listSearchProviders = Self(
        name: "list_search_providers", title: "List search providers",
        description:
            "Lists Crest's enabled search providers, their shortcuts and resolved templates, and the default provider for an allowed, unlocked Space.",
        arguments: [
            .string(
                "space", "The Space's id; defaults to the active allowed Space or first unlocked one.", required: false)
        ],
        readOnly: true, destructive: false, idempotent: true, openWorld: false)
}

extension AgentToolDefinition {
    static let openWindow = Self(
        name: "open_window", title: "Open a window",
        description:
            "At the person's request, opens a normal window over an allowed, unlocked Space, optionally at an http or https address.",
        arguments: [
            .string(
                "space", "The Space's id; defaults to the active allowed Space or first unlocked one.", required: false),
            .string("url", "The http or https address to open.", required: false),
        ], readOnly: false, destructive: false, idempotent: false, openWorld: true)
    static let openBlankWindow = Self(
        name: "open_blank_window", title: "Open a Blank Window",
        description:
            "At the person's request, opens Crest's Blank Window borrowing an allowed, unlocked Space's browsing session.",
        arguments: [
            .string(
                "space", "The Space's id; defaults to the active allowed Space or first unlocked one.", required: false)
        ],
        readOnly: false, destructive: false, idempotent: false, openWorld: true)
    static let openQuickWindow = Self(
        name: "open_quick_window", title: "Open a Quick Window",
        description:
            "At the person's request, opens an http or https address in Crest's native Quick Window using an allowed, unlocked Space.",
        arguments: [
            .string("url", "The http or https address to open."),
            .string(
                "space", "The Space's id; defaults to the active allowed Space or first unlocked one.", required: false),
        ], readOnly: false, destructive: false, idempotent: false, openWorld: true)
}
