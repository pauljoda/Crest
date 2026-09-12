import SwiftUI

/// What a tab says about the extension side panel bound to it.
///
/// The artwork lives in an installed extension package, which only the shell
/// that owns extensions can read, so it arrives here already decoded into a
/// plain SwiftUI image rather than as a platform one. `title` is written by the
/// extension: every call site renders it verbatim and never localizes it.
struct BrowserTabSidePanelPresentation: Equatable {
    let title: String
    /// The extension's own icon, drawn as authored rather than as a template.
    /// Nil where the package offers none, which is what the indicator's symbol
    /// fallback is for.
    let icon: Image?
}

/// Answers which extension side panel is bound to a given tab.
///
/// Extensions exist on the macOS shell only, so shared sidebar chrome reads
/// this out of the environment and draws nothing at all where no shell
/// supplies it.
@MainActor
protocol BrowserTabSidePanelResolving: AnyObject {
    func sidePanelPresentation(forTab tabID: TabID, in spaceID: SpaceID)
        -> BrowserTabSidePanelPresentation?
}

extension EnvironmentValues {
    @Entry var browserTabSidePanel: (any BrowserTabSidePanelResolving)? = nil
}
