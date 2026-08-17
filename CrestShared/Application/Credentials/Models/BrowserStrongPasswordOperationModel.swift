import Observation

@Observable
@MainActor
final class BrowserStrongPasswordOperationModel {

    typealias PasswordGenerator = @MainActor () throws -> String
    typealias PasswordFiller = @MainActor (String) async throws -> Void

    private(set) var phase = BrowserStrongPasswordOperationPhase.idle

    var isWorking: Bool {
        phase == .working
    }

    var hasFailed: Bool {
        phase == .failed
    }

    func generateAndFill(
        generate: PasswordGenerator = { try BrowserStrongPasswordGenerator.generate() },
        fill: PasswordFiller
    ) async {
        guard !isWorking else { return }
        phase = .working

        do {
            let password = try generate()
            try await fill(password)
            phase = .idle
        } catch {
            phase = Task.isCancelled ? .idle : .failed
        }
    }
}

enum BrowserStrongPasswordOperationPhase: Equatable, Sendable {
    case idle
    case working
    case failed
}
