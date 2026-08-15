import Foundation

enum BrowserShortcutLocalization {
    static func string(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> String {
        String(localized: Self.resource(resource, locale: locale))
    }

    static func resource(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> LocalizedStringResource {
        var localizedResource = resource
        localizedResource.locale = locale
        return localizedResource
    }

    static func list(
        _ values: [String],
        locale: Locale
    ) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: values)
            ?? values.joined(separator: ", ")
    }
}
