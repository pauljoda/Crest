import SwiftUI

extension CrestSpaceMenuPicker where Tag == SpaceID? {
    /// No Space is a legitimate state while a pane is loading.
    init(
        _ label: LocalizedStringKey,
        selection: Binding<SpaceID?>,
        spaces: [CrestSpaceIdentity],
        labelsHidden: Bool = false,
        accessibilityIdentifier: String? = nil
    ) {
        self.init(
            label: label,
            spaces: spaces,
            selection: selection,
            tag: { Optional($0.id) },
            labelsHidden: labelsHidden,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}
