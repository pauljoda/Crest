import SwiftUI

extension View {
    func crestAccessibilityValue(_ value: Text?) -> some View {
        modifier(CrestOptionalAccessibilityValue(value: value))
    }
}
