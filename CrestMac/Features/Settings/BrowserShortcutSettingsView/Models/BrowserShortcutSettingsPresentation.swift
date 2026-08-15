import Foundation

enum BrowserShortcutSettingsPresentation {
    static let emptyShortcutGlyph = "—"
    static let searchPrompt: LocalizedStringResource = "Search shortcuts"
    static let extensionSpace: LocalizedStringResource = "Extension Space"
    static let resetCrest: LocalizedStringResource = "Reset Crest"
    static let custom: LocalizedStringResource = "Custom"
    static let clearShortcut: LocalizedStringResource = "Clear Shortcut"
    static let resetToDefault: LocalizedStringResource = "Reset to Default"
    static let resetToExtensionDefault: LocalizedStringResource =
        "Reset to Extension Default"
    static let shortcutActions: LocalizedStringResource = "Shortcut Actions"
    static let shortcutAlreadyInUse: LocalizedStringResource =
        "Shortcut Already in Use"
    static let replaceExistingShortcut: LocalizedStringResource =
        "Replace Existing Shortcut"
    static let cancel: LocalizedStringResource = "Cancel"
    static let chooseAnotherShortcut: LocalizedStringResource =
        "Choose another shortcut."
    static let resetAllPrompt: LocalizedStringResource =
        "Reset all Crest shortcuts?"
    static let resetCrestShortcuts: LocalizedStringResource =
        "Reset Crest Shortcuts"
    static let resetAllDetail: LocalizedStringResource =
        "Every Crest command will return to its default shortcut."
    static let guidance: LocalizedStringResource =
        "Click a shortcut, then press a key with Command, Option, Control, or Shift. Crest commands take priority; extension commands apply only to the selected Space."
    static let invalidShortcut: LocalizedStringResource =
        "Use a supported key with Command, Option, Control, or Shift."
    static let typeShortcut: LocalizedStringResource = "Type Shortcut"
    static let unassigned: LocalizedStringResource = "Unassigned"
    static let recorderHelp: LocalizedStringResource =
        "Click, then press the new shortcut"

    static func section(
        extensionName: String,
        spaceName: String
    ) -> LocalizedStringResource {
        "\(extensionName) · \(spaceName)"
    }

    static func actionsAccessibilityLabel(
        title: String
    ) -> LocalizedStringResource {
        "Actions for \(title)"
    }

    static func recorderAccessibilityLabel(
        title: String
    ) -> LocalizedStringResource {
        "Shortcut for \(title)"
    }

    static func extensionRecorderTitle(
        extensionName: String,
        commandTitle: String
    ) -> LocalizedStringResource {
        "\(extensionName): \(commandTitle)"
    }
}
