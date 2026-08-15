import UniformTypeIdentifiers

extension BrowserTabMigrationSource {
    var allowedContentTypes: [UTType] {
        switch self {
        case .safari:
            [.propertyList, .data]
        case .chrome:
            [.data]
        case .firefox, .zen:
            [.json, .data]
        case .arc:
            [.json, .data]
        }
    }
}
