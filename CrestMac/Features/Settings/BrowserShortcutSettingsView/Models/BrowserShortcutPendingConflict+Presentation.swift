import Foundation

extension BrowserShortcutPendingConflict {
    var messageResource: LocalizedStringResource {
        messageResource()
    }

    func messageResource(
        locale: Locale = .current
    ) -> LocalizedStringResource {
        let resource: LocalizedStringResource
        if conflictingCommands.count == 1,
            let command = conflictingCommands.first
        {
            resource =
                "\(shortcut.displayString(locale: locale)) is assigned to \(command.title(locale: locale)). Replacing it will clear the shortcut from that command."
        } else {
            let titles = BrowserShortcutLocalization.list(
                conflictingCommands.map { $0.title(locale: locale) },
                locale: locale
            )
            resource =
                "\(shortcut.displayString(locale: locale)) is assigned to \(titles). Replacing it will clear the shortcut from those commands."
        }
        return BrowserShortcutLocalization.resource(
            resource,
            locale: locale
        )
    }
}
