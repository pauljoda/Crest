import Foundation

extension BrowserShortcutValidationIssue {
    var messageResource: LocalizedStringResource {
        messageResource()
    }

    func messageResource(
        locale: Locale = .current
    ) -> LocalizedStringResource {
        let resource: LocalizedStringResource =
            switch self {
            case .invalidShortcut:
                BrowserShortcutSettingsPresentation.invalidShortcut
            case .reservedByCrest(let shortcut, let commands):
                "\(shortcut.displayString(locale: locale)) is reserved by Crest for \(localizedCommandList(commands, locale: locale))."
            }
        return BrowserShortcutLocalization.resource(resource, locale: locale)
    }

    private func localizedCommandList(
        _ commands: [BrowserShortcutCommand],
        locale: Locale
    ) -> String {
        BrowserShortcutLocalization.list(
            commands.map { $0.title(locale: locale) },
            locale: locale
        )
    }
}
