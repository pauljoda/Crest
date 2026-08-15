import SwiftUI

struct BrowserInstalledImportSourceGrid: View {
    let sources: [BrowserInstalledImportSource]
    let selectedApplications: Set<BrowserImportApplication>
    let isLocked: Bool
    let accessLabel: (BrowserInstalledImportSource) -> String
    let toggleSelection: (BrowserImportApplication) -> Void

    private var rows: [[BrowserInstalledImportSource]] {
        stride(from: 0, to: sources.count, by: 3).map { start in
            Array(sources[start..<min(start + 3, sources.count)])
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(spacing: 16) {
                    ForEach(row) { source in
                        BrowserInstalledImportSourceCard(
                            source: source,
                            isSelected: selectedApplications.contains(
                                source.application
                            ),
                            isLocked: isLocked,
                            accessLabel: accessLabel(source),
                            toggleSelection: {
                                toggleSelection(source.application)
                            }
                        )
                        .frame(width: 260)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: 940)
    }
}

#Preview("Installed Browser Grid") {
    BrowserInstalledImportSourceGrid(
        sources: [BrowserOnboardingWindowPreviewFixture.importSource],
        selectedApplications: [.arc],
        isLocked: false,
        accessLabel: { _ in "Ready to review" },
        toggleSelection: { _ in }
    )
    .padding()
    .background(BrowserOnboardingPalette.parchment)
}
