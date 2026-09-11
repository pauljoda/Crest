import SwiftUI

extension Binding where Value == BrowserSpaceBranding {
    func editorUpdate(
        _ mutation: (inout BrowserSpaceBranding) -> Void
    ) {
        var updated = wrappedValue
        mutation(&updated)
        wrappedValue = updated.normalized()
    }

    func editorPreview(
        _ mutation: (inout BrowserSpaceBranding) -> Void
    ) -> BrowserSpaceBranding {
        var candidate = wrappedValue
        candidate.iconStyle = .layeredCrest
        mutation(&candidate)
        return candidate.normalized()
    }
}
