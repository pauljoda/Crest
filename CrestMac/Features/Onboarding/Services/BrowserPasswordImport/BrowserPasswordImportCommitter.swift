import Foundation

@MainActor
enum BrowserPasswordImportCommitter {
    static func commit(
        _ passwords: [BrowserImportedPassword],
        plan: BrowserImportReviewPlan,
        browser: BrowserStore
    ) async -> BrowserPasswordImportResult {
        guard !passwords.isEmpty else { return .empty }
        var recordsBySpace: [SpaceID: [BrowserCredentialCSVImportRecord]] = [:]
        var importedCount = 0
        var skippedCount = 0

        for (index, password) in passwords.enumerated() {
            let destinationIDs = destinationSpaceIDs(for: password, plan: plan)
            guard !destinationIDs.isEmpty else {
                skippedCount += 1
                continue
            }
            for spaceID in destinationIDs where browser.session.space(id: spaceID) != nil {
                recordsBySpace[spaceID, default: []].append(
                    BrowserCredentialCSVImportRecord(
                        rowNumber: index + 2,
                        displayName: password.origin.host,
                        origin: password.origin,
                        username: password.username,
                        password: password.password
                    )
                )
            }
        }

        for (spaceID, records) in recordsBySpace {
            guard let space = browser.session.space(id: spaceID) else {
                skippedCount += records.count
                continue
            }
            do {
                let existing = try await browser.credentialInventory(in: spaceID)
                let importPlan = BrowserCredentialImportPlan(
                    format: .browser,
                    records: records,
                    rejections: [],
                    existingCredentials: existing,
                    destination: BrowserSpaceRuntimeAssignment(space: space),
                    synchronizesWithICloud: space.credentialPreferences
                        .syncsCrestPasswordsWithICloud
                )
                let resolution = try importPlan.resolvedInventory()
                if resolution.summary.acceptedCount > 0 {
                    try await browser.replaceCredentialInventory(
                        resolution.credentials,
                        in: spaceID
                    )
                }
                importedCount += resolution.summary.acceptedCount
                skippedCount += resolution.summary.skippedCount
            } catch {
                skippedCount += records.count
            }
        }
        return BrowserPasswordImportResult(
            importedCount: importedCount,
            skippedCount: skippedCount
        )
    }

    static func destinationSpaceIDs(
        for password: BrowserImportedPassword,
        plan: BrowserImportReviewPlan
    ) -> [SpaceID] {
        Array(
            Set(
                sourceSpaceIDs(
                    sourceApplication: password.sourceApplication,
                    sourceProfileName: password.sourceProfileName,
                    origin: password.origin,
                    plan: plan,
                    respectsPasswordSelection: true
                ).compactMap { sourceSpaceID in
                    guard let review = plan.spaces.first(where: { $0.id == sourceSpaceID }) else {
                        return nil
                    }
                    switch review.destination {
                    case .newSpace:
                        return review.id
                    case .existing(let id):
                        return id
                    }
                }))
    }

    static func sourceSpaceIDs(
        for candidate: BrowserPasswordImportCandidate,
        plan: BrowserImportReviewPlan,
        respectsPasswordSelection: Bool
    ) -> [SpaceID] {
        sourceSpaceIDs(
            sourceApplication: candidate.sourceApplication,
            sourceProfileName: candidate.sourceProfileName,
            origin: candidate.origin,
            plan: plan,
            respectsPasswordSelection: respectsPasswordSelection
        )
    }

    private static func sourceSpaceIDs(
        sourceApplication: BrowserImportApplication,
        sourceProfileName: String,
        origin: CredentialOrigin,
        plan: BrowserImportReviewPlan,
        respectsPasswordSelection: Bool
    ) -> [SpaceID] {
        let eligibleReviews = plan.spaces.filter {
            $0.isIncluded && (!respectsPasswordSelection || $0.includesPasswords)
        }
        let profileMatch = eligibleReviews.first {
            $0.sourceSpace.name.localizedCaseInsensitiveCompare(sourceProfileName)
                == .orderedSame
        }
        let hostMatches = eligibleReviews.filter { review in
            review.sourceSpace.tabs.contains { tab in
                (tab.savedSiteURL ?? tab.url)?.host?.localizedCaseInsensitiveCompare(
                    origin.host
                ) == .orderedSame
            }
        }
        let matches: [BrowserImportSpaceReview]
        switch sourceApplication {
        case .chrome:
            matches =
                profileMatch.map { [$0] }
                ?? hostMatches.first.map { [$0] }
                ?? eligibleReviews.first.map { [$0] }
                ?? []
        case .arc:
            matches = hostMatches
        case .zen, .safari, .firefox:
            matches = []
        }
        return matches.map(\.id)
    }
}
