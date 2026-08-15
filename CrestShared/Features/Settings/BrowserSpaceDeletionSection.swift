import SwiftUI

struct BrowserSpaceDeletionSection: View {
    let browser: BrowserStore
    let spaceID: SpaceID
    let dataDeleter: any BrowserSpaceDataDeleting

    @State private var isConfirmingDeletion = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        Section("Delete Space") {
            Button(
                isDeleting ? "Deleting Space…" : "Delete \(spaceName)…",
                systemImage: "trash",
                role: .destructive
            ) {
                isConfirmingDeletion = true
            }
            .disabled(isDeleting || browser.session.spaces.count <= 1)
            .accessibilityIdentifier("delete-selected-space")

            if isDeleting {
                ProgressView("Removing private browser data…")
                    .accessibilityIdentifier("space-deletion-progress")
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("space-deletion-error")
            }

            Text(disclosure)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("space-deletion-disclosure")
        }
        .alert(
            "Delete “\(spaceName)”?",
            isPresented: $isConfirmingDeletion
        ) {
            Button("Delete Space and Data", role: .destructive) {
                deleteSpace()
            }
            .accessibilityIdentifier("confirm-delete-space")

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently removes this Space’s browser data from Crest. "
                    + "Downloaded files you already saved are kept."
            )
        }
    }

    private var spaceName: String {
        browser.session.space(id: spaceID)?.name ?? "Space"
    }

    private var disclosure: String {
        if browser.session.spaces.count <= 1 {
            return "Crest needs at least one Space. Add another Space before deleting this one."
        }
        return "Deletes tabs, pins, folders, Archive, history, Crest Passwords, cookies, "
            + "website storage, permissions, extension packages and storage, and download "
            + "history. Downloaded files are kept. This can’t be undone."
    }

    private func deleteSpace() {
        errorMessage = nil
        isDeleting = true
        Task { @MainActor in
            defer { isDeleting = false }
            do {
                try await browser.deleteSpace(
                    spaceID,
                    dataDeleter: dataDeleter
                )
            } catch {
                errorMessage = "\(error.localizedDescription) The Space was kept so you can try again."
            }
        }
    }
}

#Preview("Space Deletion") {
    let browser = BrowserStore.preview()
    Form {
        BrowserSpaceDeletionSection(
            browser: browser,
            spaceID: browser.session.spaces[0].id,
            dataDeleter: BrowserSettingsPreviewDataDeleter()
        )
    }
}
