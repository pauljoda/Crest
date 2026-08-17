import SwiftUI

struct BrowserUtilityListBlankState: View {
    let dismiss: (() -> Void)?

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .onTapGesture {
                dismiss?()
            }
            .accessibilityHidden(true)
    }
}
