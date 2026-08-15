import SwiftUI

extension View {
    func crestAccessibilityIdentifier(_ identifier: String?) -> some View {
        modifier(CrestOptionalAccessibilityIdentifier(identifier: identifier))
    }
}
