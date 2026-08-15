import Foundation

struct BrowserOnboardingPreviewImportReader: BrowserOnboardingImportReading {
    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        throw CancellationError()
    }
}
