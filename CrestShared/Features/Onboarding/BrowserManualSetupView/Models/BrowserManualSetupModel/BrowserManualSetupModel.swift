import Foundation
import Observation

@MainActor
@Observable
final class BrowserManualSetupModel {
    // MARK: - Types

    /// What a preview answers for: the plan, and the session of the browser
    /// it was drafted over as that browser last changed it.
    private struct PreviewInputs: Equatable {
        let plan: BrowserManualSetupPlan
        let browser: ObjectIdentifier
        let sessionRevision: Int
    }

    // MARK: - Variables

    var address: String
    var placement: TabPlacement
    var errorMessage: String?
    /// What the core said the setup would leave, until the plan or the
    /// session changes, so a view's body never asks it again.
    @ObservationIgnored private var preview: (inputs: PreviewInputs, session: BrowserSession?)?

    var canAddAddress: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Initializers

    init(
        address: String = "",
        placement: TabPlacement = .saved,
        errorMessage: String? = nil
    ) {
        self.address = address
        self.placement = placement
        self.errorMessage = errorMessage
    }

    // MARK: - Actions - Preview

    /// The session the setup would leave `browser`'s workspace with, or nil
    /// when the core would refuse it. The core answers once each time the
    /// plan or the workspace's session changes.
    func previewSession(
        for plan: BrowserManualSetupPlan,
        in browser: BrowserStore
    ) -> BrowserSession? {
        let inputs = PreviewInputs(
            plan: plan, browser: ObjectIdentifier(browser), sessionRevision: browser.sessionRevision)
        if let preview, preview.inputs == inputs { return preview.session }
        let session = try? plan.preview(in: browser)
        preview = (inputs, session)
        return session
    }
}
