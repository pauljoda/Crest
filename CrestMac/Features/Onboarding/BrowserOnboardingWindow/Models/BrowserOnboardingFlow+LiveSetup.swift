import Foundation

/// Setup as one window of steps beside a live preview of the browser it
/// builds. The manual setup starts with setup, so every step edits the same
/// Spaces; one browser at a time comes in as it is, with no review; and the
/// import is applied only when the person starts browsing.
extension BrowserOnboardingFlow {
    // MARK: - Variables

    /// The browser chosen to bring tabs from, while one is.
    var chosenSource: BrowserInstalledImportSource? {
        offeredSources.first(where: isSelected)
    }

    /// Whether the chosen browser's Spaces are ready to preview and bring in.
    var hasIncomingSpaces: Bool {
        review?.hasIncludedSpaces == true
    }

    /// The Spaces the chosen browser brings in new, which the preview marks.
    var incomingSpaceIDs: Set<UUID> {
        Set(reviewSpaces.filter { $0.isIncluded && $0.destination.spaceID == nil }.map(\.id))
    }

    /// The Space the preview opens on once the chosen browser's Spaces are
    /// read: the first one it brings.
    var firstIncomingPreviewSpaceID: UUID? {
        reviewSpaces.first(where: \.isIncluded).map(previewSpaceID)
    }

    /// The browser setup would leave: the import of the chosen browser when
    /// there is one, with the manual setup's names and looks on the Spaces it
    /// holds, or else the manual setup applied.
    var setupPreview: BrowserSessionPreview? {
        if hasIncomingSpaces, case .success(let preview) = reviewPreview() {
            return preview.wearing(manualSetup.draft)
        }
        return draftPreview.preview(of: manualSetup, in: browser)
    }

    /// The session setup would leave, as a window of Crest opens over it,
    /// with the images its tabs wear: the chosen browser's import with the
    /// manual setup's names and looks, or else the manual setup applied.
    var setupSession: BrowserSetupSession? {
        if hasIncomingSpaces, case .success(let preview) = reviewPreview() {
            return BrowserSetupSession(seed: preview.seed(wearing: manualSetup.draft), images: preview.images)
        }
        guard let preview = draftPreview.preview(of: manualSetup, in: browser) else { return nil }
        return BrowserSetupSession(seed: preview.seed(wearing: nil), images: preview.images)
    }

    /// Whether the chosen browser's passwords come in.
    var includesPasswords: Bool {
        reviewSpaces.contains { $0.isIncluded && $0.record.includesPasswords }
    }

    /// How many saved passwords the chosen browser keeps.
    var passwordCount: Int {
        reviewSpaces.reduce(0) { $0 + $1.record.passwordCount }
    }

    /// How many of the passwords that come in are for sites without HTTPS,
    /// which are never filled in automatically.
    var insecurePasswordCount: Int {
        reviewSpaces.filter { $0.isIncluded && $0.record.includesPasswords }
            .reduce(0) { $0 + $1.record.insecurePasswordCount }
    }

    /// Whether the chosen browser's extensions come in.
    var includesExtensions: Bool {
        reviewSpaces.contains { !$0.includedExtensionIDs.isEmpty }
    }

    /// How many extensions the chosen browser offers.
    var extensionCount: Int {
        Set(reviewSpaces.flatMap { $0.extensions.map(\.extensionID) }).count
    }

    // MARK: - Functions

    /// The Space of the preview that `review` shows as: the Space it joins,
    /// or its own.
    func previewSpaceID(of review: BrowserImportSpaceReview) -> UUID {
        review.destination.spaceID ?? review.id
    }

    // MARK: - Actions - Live setup

    /// Starts the manual setup with setup, so the Spaces step and the preview
    /// work from the first page.
    func beginLiveSetup() {
        guard manualSetup.draft == nil, state?.phase.isBusy != true else { return }
        show(.manualSetup)
    }

    /// Chooses `source` as the one browser to bring tabs from, reading it at
    /// once, or leaves it out when it is the one chosen.
    func chooseSource(_ source: BrowserInstalledImportSource) {
        guard !isImportSelectionLocked else { return }
        let wasChosen = isSelected(source)
        for other in offeredSources where other.id != source.id && isSelected(other) {
            toggleSelection(other)
        }
        toggleSelection(source)
        guard !wasChosen else { return }
        continueImportQueue()
    }

    /// Reads the chosen browser again after reading it failed, from its own
    /// folder or, when that holds nothing, the folder the person picks.
    func readChosenSourceAgain() {
        guard let source = chosenSource else { return }
        chooseSource(source)
        chooseSource(source)
    }

    /// Brings the chosen browser's passwords in, or leaves them out, for every
    /// Space it brings.
    func setPasswordsIncluded(_ isIncluded: Bool) {
        for review in reviewSpaces where review.record.passwordCount > 0 {
            setPasswordsIncluded(isIncluded, in: review.id)
        }
    }

    /// Brings the chosen browser's extensions in, or leaves them out, for every
    /// Space it brings.
    func setExtensionsIncluded(_ isIncluded: Bool) {
        for review in reviewSpaces {
            setExtensionsIncluded(isIncluded, in: review.id)
        }
    }

    /// Starts browsing: applies the chosen browser's import when there is one,
    /// then finishes setup with the manual setup applied, and makes `edits`,
    /// what the person changed in the preview's tabs and folders, in Crest
    /// before it opens.
    func startBrowsing(
        progress: BrowserOnboardingProgressStore,
        spaceAccess: BrowserSpaceAccessController,
        carrying edits: BrowserSetupCopyEdits? = nil,
        onCompleted: @escaping @MainActor () -> Void
    ) {
        guard !isImportSelectionLocked else { return }
        let browser = self.browser
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            show(.manualSetup)
            completeSetup(progress: progress, spaceAccess: spaceAccess) {
                edits?.replay(into: browser)
                onCompleted()
            }
        }
        guard hasIncomingSpaces else {
            finish()
            return
        }
        afterImport = finish
        commitReviewedImport()
    }
}
