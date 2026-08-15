import SwiftUI

struct BrowserTabSavedLocationIndicator: View {
    let restore: () -> Void

    var body: some View {
        Text(verbatim: "/")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
            .frame(width: 14, height: CrestLayout.minimumHitTarget)
            .contentShape(.rect)
            .onTapGesture(count: 2, perform: restore)
            .help("Away from saved location — double-click to return")
            .accessibilityElement()
            .accessibilityLabel("Away from saved location")
            .accessibilityHint("Double-click to return to the saved URL")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text("Return to Saved URL"), restore)
    }

}

#Preview("Saved Location Indicator", traits: .sizeThatFitsLayout) {
    BrowserTabSavedLocationIndicator(restore: {})
        .padding()
}
