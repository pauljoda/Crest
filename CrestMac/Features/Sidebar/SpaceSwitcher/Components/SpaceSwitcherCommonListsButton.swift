import SwiftUI

struct SpaceSwitcherCommonListsButton: View {
    let isExpanded: Bool
    let action: () -> Void
    let recordFrame: (CGRect) -> Void

    var body: some View {
        Button("Common Lists", systemImage: "archivebox", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: 32, height: 32)
            .symbolVariant(isExpanded ? .fill : .none)
            .help("Archive, History, and Downloads")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("common-lists-button")
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                recordFrame(frame)
            }
    }
}

#Preview("Common Lists Button") {
    SpaceSwitcherCommonListsButton(
        isExpanded: false,
        action: {},
        recordFrame: { _ in }
    )
    .padding()
}
