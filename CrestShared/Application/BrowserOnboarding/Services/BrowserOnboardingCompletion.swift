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
        // The core decides whether finishing opens the guide; a private store
        // never consumes the install's setup completion.
        guard let outcome = BrowserCorePolicy.onboardingCompletion(
            entryPoint: request.entryPoint, hasCompletedSetup: !progress.willOpenGettingStarted,
            isPrivateBrowsing: browser.isPrivateBrowsing), outcome != .sourceChanged
        else { return .sourceChanged }
        let originalSession = browser.session
        let proposedSession: BrowserSession
        do {
            proposedSession = try manualPlan?.preview(mergingInto: originalSession) ?? originalSession
        } catch {
            return .sourceChanged
        }
        guard outcome == .openGuide else {
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
        let currentSession = browser.session
        let guideSpace = manualPlan.map { plan in
            (try? plan.preview(mergingInto: currentSession))?.spaces.first
        } ?? currentSession.spaces.first
        guard BrowserCorePolicy.confirmsOnboardingGuide(
            target: assignment,
            originalFirst: originalSession.spaces.first.map(BrowserSpaceRuntimeAssignment.init(space:)),
            currentFirst: currentSession.spaces.first.map(BrowserSpaceRuntimeAssignment.init(space:)),
            originalTarget: originalSession.space(id: assignment.spaceID).map(BrowserSpaceRuntimeAssignment.init(space:)),
            currentTarget: currentSession.space(id: assignment.spaceID).map(BrowserSpaceRuntimeAssignment.init(space:)),
            previewFirst: manualPlan == nil ? nil : guideSpace.map(BrowserSpaceRuntimeAssignment.init(space:)),
            hasManualPlan: manualPlan != nil,
            isLocked: guideSpace.map(spaceAccess.isLocked) ?? true)
        else { return .sourceChanged }
        if let manualPlan {
            do { try browser.commitManualSetup(manualPlan) } catch { return .sourceChanged }
        }
        guard let guide = browser.openGettingStartedAfterSetup(matching: assignment) else { return .sourceChanged }
        willComplete(guide)
        _ = progress.completeSetup(for: request.entryPoint)
        return .completed(guide: guide)
    }
}
