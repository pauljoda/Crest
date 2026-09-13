@MainActor
enum BrowserOnboardingCompletion {
    enum Result: Equatable {
        case completed(guide: BrowserTabRuntimeAssignment?)
        case cancelled
        case sourceChanged
    }

    static func complete(
        request: BrowserOnboardingRequest,
        browser: BrowserStore,
        progress: BrowserOnboardingProgressStore,
        spaceAccess: BrowserSpaceAccessController,
        manualPlan: BrowserManualSetupPlan? = nil,
        willComplete: @MainActor (BrowserTabRuntimeAssignment?) -> Void = { _ in }
    ) async -> Result {
        guard !Task.isCancelled else { return .cancelled }
        guard !browser.isPrivateBrowsing else { return .sourceChanged }
        let originalSession = browser.session
        let proposedSession: BrowserSession
        do {
            proposedSession = try manualPlan?.preview(mergingInto: originalSession) ?? originalSession
        } catch {
            return .sourceChanged
        }
        guard progress.willOpenGettingStarted(for: request.entryPoint) else {
            if let manualPlan {
                do { try browser.commitManualSetup(manualPlan) } catch { return .sourceChanged }
            }
            willComplete(nil)
            _ = progress.completeSetup(for: request.entryPoint)
            return .completed(guide: nil)
        }
        guard let firstSpace = proposedSession.spaces.first else { return .sourceChanged }
        let assignment = BrowserSpaceRuntimeAssignment(space: firstSpace)
        guard await spaceAccess.unlock(firstSpace), !Task.isCancelled else { return .cancelled }
        if let manualPlan {
            guard
                browser.session.spaces.first.map(BrowserSpaceRuntimeAssignment.init(space:))
                    == originalSession.spaces.first.map(BrowserSpaceRuntimeAssignment.init(space:)),
                browser.session.space(id: assignment.spaceID).map(BrowserSpaceRuntimeAssignment.init(space:))
                    == originalSession.space(id: assignment.spaceID).map(BrowserSpaceRuntimeAssignment.init(space:)),
                let updatedPreview = try? manualPlan.preview(mergingInto: browser.session),
                let updatedFirst = updatedPreview.spaces.first,
                BrowserSpaceRuntimeAssignment(space: updatedFirst) == assignment,
                !spaceAccess.isLocked(updatedFirst)
            else { return .sourceChanged }
            do { try browser.commitManualSetup(manualPlan) } catch { return .sourceChanged }
        } else {
            guard let currentSpace = browser.session.spaces.first,
                BrowserSpaceRuntimeAssignment(space: currentSpace) == assignment,
                !spaceAccess.isLocked(currentSpace)
            else { return .sourceChanged }
        }
        guard let guide = browser.openGettingStartedAfterSetup(matching: assignment) else { return .sourceChanged }
        willComplete(guide)
        _ = progress.completeSetup(for: request.entryPoint)
        return .completed(guide: guide)
    }
}
