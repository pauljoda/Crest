import Foundation

/// The content bridge that hides what the content filter hides in a page's
/// documents beyond what the page's engine blocks, and runs the element picker
/// in the top document. The canonical JavaScript source lives in `CrestCore` so
/// every platform and engine runs the same script.
@MainActor
enum BrowserCosmeticFilterContentBridge {
    // MARK: - Static Variables

    static let messageHandlerName = ContentBridge.cosmeticFilter.handlerName

    /// Applies an answer, `answer`, in the document that asked.
    static let applyBody = "globalThis.__crestCosmetics?.apply(answer); return true;"
    /// Starts the element picker in the top document with `options`: the
    /// colour its highlight takes and whether it starts from what the person
    /// last right-clicked. Answers whether it started.
    static let pickBody = "return globalThis.__crestCosmetics?.pick(options) ?? false;"
    /// Gives the running picker one of the bar's commands, `command`.
    static let pickerCommandBody = "globalThis.__crestCosmetics?.command(command); return true;"

    static let source: String = ContentBridge.cosmeticFilter.script().source

    // MARK: - Actions - Options

    /// What `pickBody` passes the picker: Crest's accent, which outlines what
    /// the person points at as it tints the bar's Block button, and whether
    /// it starts from what they last right-clicked.
    static func pickerOptions(fromContextMenu: Bool) -> [String: Any] {
        let accent = CrestBrandTheme.accentLightComponents
        return [
            "accent": "rgb(\(accent.red) \(accent.green) \(accent.blue))",
            "fromContextMenu": fromContextMenu,
        ]
    }
}
