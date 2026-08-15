import SwiftUI

extension BrowserRootModel {
    /// Native text controls may write their current value while reconciling.
    /// Deduplicating that write keeps Observation from invalidating the entire
    /// sidebar for a value that did not actually change.
    var addressBinding: Binding<String> {
        Binding(
            get: { self.address },
            set: { address in
                guard self.address != address else { return }
                self.address = address
            }
        )
    }

    var isAddressEditingBinding: Binding<Bool> {
        Binding(
            get: { self.isAddressEditing },
            set: { isEditing in
                guard self.isAddressEditing != isEditing else { return }
                self.isAddressEditing = isEditing
            }
        )
    }

    var isWindowFocusedBinding: Binding<Bool> {
        Binding(
            get: { self.isWindowFocused },
            set: { isFocused in
                guard self.isWindowFocused != isFocused else { return }
                self.isWindowFocused = isFocused
            }
        )
    }
}
