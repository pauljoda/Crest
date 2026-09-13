import Foundation

struct BrowserSearchEngineEditorRequest: Hashable, Identifiable {
    let id: UUID
    let name: String
    let searchURLTemplate: String
    let suggestionURLTemplate: String
    let isNew: Bool

    static func new() -> Self {
        Self(
            id: UUID(),
            name: "",
            searchURLTemplate: "",
            suggestionURLTemplate: "",
            isNew: true
        )
    }

    static func edit(_ provider: BrowserCustomSearchProvider) -> Self {
        Self(
            id: provider.id,
            name: provider.name,
            searchURLTemplate: provider.searchURLTemplate,
            suggestionURLTemplate: provider.suggestionURLTemplate ?? "",
            isNew: false
        )
    }
}
