import SwiftUI

extension View {
    /// Asks before `change` moves a Space into or out of a group, unlocks the
    /// Spaces it names, then applies it. A refusal or a failed unlock shows a
    /// notice; the first group a device forms reminds the person to update
    /// Crest elsewhere.
    func browserSpaceGroupChangeConfirmation(
        _ change: Binding<BrowserSpaceGroupChange?>,
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController
    ) -> some View {
        modifier(BrowserSpaceGroupChangeConfirmation(change: change, browser: browser, spaceAccess: spaceAccess))
    }

    /// Asks before deleting the Space `request` names, as its plan describes:
    /// a primary that leads Sub-Spaces asks which of them takes its group
    /// over. Then deletes it and its data, reporting a failure.
    func browserSpaceDeletionConfirmation(
        _ request: Binding<BrowserSpaceDeletionRequest?>,
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        dataDeleter: any BrowserSpaceDataDeleting
    ) -> some View {
        modifier(
            BrowserSpaceDeletionConfirmation(
                request: request, browser: browser, spaceAccess: spaceAccess, dataDeleter: dataDeleter))
    }
}

private struct BrowserSpaceGroupChangeConfirmation: ViewModifier {
    @Binding var change: BrowserSpaceGroupChange?
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    func body(content: Content) -> some View {
        content.alert(
            change?.title ?? "",
            isPresented: Binding(get: { change != nil }, set: { if !$0 { change = nil } }),
            presenting: change
        ) { change in
            Button(change.confirmation) { apply(change) }
                .accessibilityIdentifier("confirm-space-group-change")
            Button("Cancel", role: .cancel) {}
        } message: { change in
            Text(change.message)
        }
    }

    private func apply(_ change: BrowserSpaceGroupChange) {
        self.change = nil
        Task { @MainActor in
            // The change redraws much of the window, so the confirmation
            // finishes closing on screen first instead of hanging over it.
            try? await Task.sleep(for: .seconds(CrestMotion.dismissalTransition))
            for space in change.unlocking {
                guard await spaceAccess.unlock(space) else { return }
            }
            do throws(Rejection) {
                try change.apply(in: browser)
                if change.formsGroup { BrowserSpaceGroupNotices.formed() }
            } catch {
                BrowserSpaceGroupNotices.failed(error.localizedDescription)
            }
        }
    }
}

private struct BrowserSpaceDeletionConfirmation: ViewModifier {
    @Binding var request: BrowserSpaceDeletionRequest?
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    @State private var failure: String?

    func body(content: Content) -> some View {
        let plan = request.flatMap { BrowserSpaceDeletionPlan($0, in: browser) }
        content
            .alert(
                plan?.title ?? "",
                isPresented: Binding(
                    get: { plan.map { $0.successors.isEmpty } == true }, set: { if !$0 { request = nil } }),
                presenting: plan
            ) { plan in
                Button(plan.confirmation, role: .destructive) { delete(plan, successor: nil) }
                    .accessibilityIdentifier("confirm-delete-space")
                Button("Cancel", role: .cancel) {}
            } message: { plan in
                Text(plan.message)
            }
            #if os(macOS)
                .sheet(isPresented: choosesSuccessor(plan)) {
                    if let plan {
                        BrowserSpaceSuccessorSheet(plan: plan) { successor in delete(plan, successor: successor) }
                    }
                }
            #else
                .confirmationDialog(
                    plan?.title ?? "", isPresented: choosesSuccessor(plan), titleVisibility: .visible, presenting: plan
                ) { plan in
                    ForEach(plan.successors) { space in
                        Button("\(space.settings.name) Keeps the Group", role: .destructive) {
                            delete(plan, successor: space.id)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { plan in
                    Text(plan.message)
                }
            #endif
            .alert(
                "Couldn’t Delete Space",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
            ) {
                Button("OK") { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }

    /// Whether the person chooses which Sub-Space keeps the group of the
    /// primary `plan` deletes.
    private func choosesSuccessor(_ plan: BrowserSpaceDeletionPlan?) -> Binding<Bool> {
        Binding(get: { plan.map { !$0.successors.isEmpty } == true }, set: { if !$0 { request = nil } })
    }

    private func delete(_ plan: BrowserSpaceDeletionPlan, successor: UUID?) {
        request = nil
        Task { @MainActor in
            if let space = plan.unlocking, !(await spaceAccess.unlock(space)) { return }
            do {
                try await plan.run(in: browser, successor: successor, dataDeleter: dataDeleter)
            } catch {
                // The page that asked may be gone with the Space, so the window says it too.
                let message = "\(error.localizedDescription) The Space was kept so you can try again."
                failure = message
                BrowserSpaceGroupNotices.failed(message)
            }
        }
    }
}

#if os(macOS)
    /// Asks which Sub-Space takes over the group of a primary that is deleted.
    private struct BrowserSpaceSuccessorSheet: View {
        let plan: BrowserSpaceDeletionPlan
        let delete: (UUID) -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var successorID: UUID?

        var body: some View {
            VStack(alignment: .leading, spacing: CrestSpacing.large) {
                Text(plan.title).font(.headline)
                Text(plan.message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Picker("New primary", selection: $successorID) {
                    ForEach(plan.successors) { space in
                        Label {
                            Text(space.settings.name)
                        } icon: {
                            BrowserSpaceIdentityIcon(space: space, size: 16)
                        }
                        .tag(Optional(space.id))
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("space-deletion-successor")
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(plan.confirmation, role: .destructive) {
                        guard let successorID else { return }
                        dismiss()
                        delete(successorID)
                    }
                    .disabled(successorID == nil)
                    .accessibilityIdentifier("confirm-delete-space")
                }
            }
            .padding(20)
            .frame(width: 380)
            .onAppear { successorID = successorID ?? plan.successors.first?.id }
        }
    }
#endif
