import Foundation

@MainActor
enum BrowserPasswordImportCommitter {
    static func commit(
        _ passwords: [BrowserImportedPassword],
        plan: BrowserImportReviewPlan,
        browser: BrowserStore
    ) async -> BrowserPasswordImportResult {
        guard !passwords.isEmpty else { return .empty }
        var descriptorsBySpace: [SpaceID: [CredentialDescriptor]] = [:]
        var importedCount = 0
        var skippedCount = 0

        for password in passwords {
            guard let originURL = URL(string: password.origin.description) else {
                skippedCount += 1
                continue
            }
            let destinationIDs = destinationSpaceIDs(for: password, plan: plan)
            guard !destinationIDs.isEmpty else {
                skippedCount += 1
                continue
            }
            for spaceID in destinationIDs where browser.session.space(id: spaceID) != nil {
                if descriptorsBySpace[spaceID] == nil {
                    descriptorsBySpace[spaceID] =
                        (try? await browser.savedCredentialDescriptors(
                            in: spaceID
                        )) ?? []
                }
                let isDuplicate = descriptorsBySpace[spaceID, default: []].contains {
                    $0.origin == password.origin && $0.username == password.username
                }
                guard !isDuplicate else {
                    skippedCount += 1
                    continue
                }
                do {
                    let descriptor = try await browser.saveCredential(
                        username: password.username,
                        password: password.password,
                        for: originURL,
                        in: spaceID,
                        displayName: password.origin.host
                    )
                    descriptorsBySpace[spaceID, default: []].append(descriptor)
                    importedCount += 1
                } catch {
                    skippedCount += 1
                }
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
