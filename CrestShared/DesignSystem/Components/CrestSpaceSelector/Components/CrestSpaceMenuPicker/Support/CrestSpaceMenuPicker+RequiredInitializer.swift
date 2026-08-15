import SwiftUI

extension CrestSpaceMenuPicker where Tag == SpaceID {
    /// Use for preferences that always resolve to a Space.
    init(
        _ label: LocalizedStringKey,
        selection: Binding<SpaceID>,
        spaces: [CrestSpaceIdentity],
        labelsHidden: Bool = false,
        accessibilityIdentifier: String? = nil
    ) {
        self.init(
            label: label,
            spaces: spaces,
            selection: selection,
            tag: \.id,
            labelsHidden: labelsHidden,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}
