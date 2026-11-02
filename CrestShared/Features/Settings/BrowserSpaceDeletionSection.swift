import SwiftUI

struct BrowserSpaceDeletionSection: View {
    let browser: BrowserStore
    let spaceID: UUID
    let dataDeleter: any BrowserSpaceDataDeleting

    @State private var isConfirmingDeletion = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var successorID: UUID?

    var body: some View {
        let plan = BrowserSpaceDeletionPlan(BrowserSpaceDeletionRequest(spaceID: spaceID), in: browser)
        Section {
            // A primary that leads Sub-Spaces names the one that takes its group over.
            if let plan, !plan.successors.isEmpty {
                Picker("Keeps the Group", selection: successor(in: plan)) {
                    ForEach(plan.successors) { space in
                        Text(space.settings.name).tag(Optional(space.id))
                    }
                }
                .accessibilityIdentifier("space-deletion-successor")
            }

            Button(
                isDeleting ? "Deleting Space…" : "Delete “\(spaceName)”…",
                role: .destructive
            ) {
                isConfirmingDeletion = true
            }
            .disabled(isDeleting || browser.spaceModels.count <= 1)
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

        } footer: {
            Text(disclosure(plan))
                .crestFormFootnote()
                .accessibilityIdentifier("space-deletion-disclosure")
        }
        .alert(
            plan?.title ?? "",
            isPresented: $isConfirmingDeletion,
            presenting: plan
        ) { plan in
            Button(plan.confirmation, role: .destructive) {
                deleteSpace(plan)
            }
            .accessibilityIdentifier("confirm-delete-space")

            Button("Cancel", role: .cancel) {}
        } message: { plan in
            Text(plan.message)
        }
    }

    private var spaceName: String {
        browser.spaceModel(spaceID)?.settings.name ?? "Space"
    }

    /// The Sub-Space chosen to take the group over, the first until one is.
    private func successor(in plan: BrowserSpaceDeletionPlan) -> Binding<UUID?> {
        Binding(
            get: {
                successorID.flatMap { id in plan.successors.contains { $0.id == id } ? id : nil }
                    ?? plan.successors.first?.id
            },
            set: { successorID = $0 })
    }

    private func disclosure(_ plan: BrowserSpaceDeletionPlan?) -> String {
        if browser.spaceModels.count <= 1 {
            return String(localized: "Crest needs at least one Space.")
        }
        guard let space = browser.spaceModel(spaceID) else { return "" }
        if browser.isSubSpace(space) {
            return String(
                localized: "Deletes this Sub-Space’s tabs. Its group keeps its sign-ins, history and passwords.")
        }
        if plan?.successors.isEmpty == false {
            return String(
                localized: """
                    Deletes this Space’s tabs. The Space chosen above keeps its group’s sign-ins, history and \
                    passwords.
                    """)
        }
        return String(localized: "Deletes everything in this Space except downloaded files.")
    }

    private func deleteSpace(_ plan: BrowserSpaceDeletionPlan) {
        errorMessage = nil
        isDeleting = true
        let chosen = successor(in: plan).wrappedValue
        Task { @MainActor in
            defer { isDeleting = false }
            do {
                try await plan.run(in: browser, successor: chosen, dataDeleter: dataDeleter)
            } catch {
                errorMessage = "\(error.localizedDescription) The Space was kept so you can try again."
            }
        }
    }
}
