import SwiftUI

extension Binding where Value == BrowserSpaceBranding {
    func editorUpdate(
        _ mutation: (inout BrowserSpaceBranding) -> Void
    ) {
        var updated = wrappedValue
        mutation(&updated)
        wrappedValue = updated.normalized()
    }
}
