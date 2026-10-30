import SwiftUI

/// The headers Tidy made, each with the titles of the tabs it would file,
/// shown for the person to apply all at once or cancel.
struct BrowserTidyPreview: View {
    let headers: [TidyFolderProposal]
    let tabTitle: (UUID) -> String
    let cancel: () -> Void
    let apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            ScrollView {
                VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                    ForEach(Array(shownHeaders.enumerated()), id: \.offset) { _, header in
                        VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                            Text(header.folderTitle).font(.headline)
                            ForEach(header.tabIDs, id: \.self) { tabID in
                                Text(tabTitle(tabID))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: apply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(CrestSpacing.large)
        .frame(width: 280)
    }

    /// One row per name, as the core files groups named alike under one
    /// header.
    private var shownHeaders: [TidyFolderProposal] {
        var shown: [TidyFolderProposal] = []
        for header in headers {
            if let index = shown.firstIndex(where: { $0.folderTitle.lowercased() == header.folderTitle.lowercased() }) {
                shown[index].tabIDs += header.tabIDs
            } else {
                shown.append(header)
            }
        }
        return shown
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserTidyPreview(
            headers: [
                TidyFolderProposal(folderTitle: "Knitting", tabIDs: [UUID(), UUID()]),
                TidyFolderProposal(folderTitle: "Docker", tabIDs: [UUID(), UUID(), UUID()]),
            ],
            tabTitle: { _ in "A page title" }, cancel: {}, apply: {})
    }
#endif
