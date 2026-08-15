import SwiftUI

struct BrowserExtensionAccessSection: View {
    let title: LocalizedStringKey
    let values: [String]
    let decision: (String) -> BrowserExtensionAccessDecision
    let setDecision: (String, BrowserExtensionAccessDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(values, id: \.self) { value in
                HStack(spacing: CrestSpacing.medium) {
                    Text(value)
                        .font(.caption)
                        .textSelection(.enabled)
                    Spacer(minLength: CrestSpacing.small)
                    Picker(
                        value,
                        selection: Binding(
                            get: { decision(value) },
                            set: { setDecision(value, $0) }
                        )
                    ) {
                        ForEach(BrowserExtensionAccessDecision.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
    }
}

#Preview("Extension Access", traits: .sizeThatFitsLayout) {
    BrowserExtensionAccessSection(
        title: "Website Access",
        values: ["https://developer.apple.com/*", "https://swift.org/*"],
        decision: { _ in .ask },
        setDecision: { _, _ in }
    )
    .padding()
}
