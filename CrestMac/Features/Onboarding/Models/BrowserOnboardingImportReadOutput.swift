struct BrowserOnboardingImportReadOutput: Sendable {
    let payload: BrowserDetectedImportPayload
    let imported: BrowserPortableImport
    let passwordCandidates: [BrowserPasswordImportCandidate]
}
