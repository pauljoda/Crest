import Foundation
import FoundationModels

/// Keyphrases Apple's on-device model writes for open tabs in the background
/// while Tidy is on, so pressing Tidy only has to group and name them.
///
/// One tab is described at a time, the most recently asked-for first, and
/// none while a Tidy runs: a description beside Tidy's naming call triples the
/// wait. Keyphrases stay in memory on this device, keyed by the tab's title,
/// host and path, and are never persisted, synced or logged.
@MainActor
final class TidyTabDescriptions {
    // MARK: - Static Variables

    static let shared = TidyTabDescriptions()

    /// Enough for every loose tab in several busy Spaces; the oldest go first.
    private static let maximumCachedDescriptions = 1000
    private static let maximumKeyphrases = 5

    /// Five short lines with room to spare, which stops a runaway answer.
    private static let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 128)

    private static let instructions = """
        You describe one open browser tab in five short keyphrases: what the person is working on, shopping \
        for or reading about, from specific to broad, ending with the broad project or subject it belongs to. \
        Never name the website. Write one keyphrase per line, with no numbering.
        """

    // MARK: - Variables

    private var keyphrasesByDescription: [String: [String]] = [:]
    private var describedOrder: [String] = []
    private var waiting: [TidyTabCandidate] = []
    private var worker: Task<Void, Never>?
    /// Which worker `worker` holds, so one that was cancelled leaves a newer
    /// one's handle alone when it ends.
    private var workerID: UUID?
    private var pauseCount = 0

    // MARK: - Actions - Reading

    /// The keyphrases written for `candidate`'s current title and address, or
    /// nil while it has none.
    func keyphrases(for candidate: TidyTabCandidate) -> [String]? {
        keyphrasesByDescription[candidate.modelDescription]
    }

    // MARK: - Actions - Queueing

    /// Describes each of `candidates` not yet described, ahead of tabs asked
    /// for earlier.
    func describe(_ candidates: [TidyTabCandidate]) {
        let undescribed = candidates.filter { keyphrasesByDescription[$0.modelDescription] == nil }
        let undescribedDescriptions = Set(undescribed.map(\.modelDescription))
        waiting = undescribed + waiting.filter { !undescribedDescriptions.contains($0.modelDescription) }
        startWorkingIfIdle()
    }

    /// Runs `body` with no description starting meanwhile. One already under
    /// way finishes.
    func pausing<Result>(_ body: () async throws -> Result) async rethrows -> Result {
        pauseCount += 1
        defer {
            pauseCount -= 1
            startWorkingIfIdle()
        }
        return try await body()
    }

    /// Stops describing and drops the tabs waiting for it, keeping the
    /// keyphrases already written, as while Apple Intelligence is unavailable.
    func stopDescribing() {
        worker?.cancel()
        worker = nil
        waiting = []
    }

    /// Drops every description and stops describing, as when history is
    /// cleared or Tidy is turned off.
    func forgetAll() {
        stopDescribing()
        keyphrasesByDescription = [:]
        describedOrder = []
    }

    // MARK: - Actions - Describing

    private func startWorkingIfIdle() {
        guard worker == nil, pauseCount == 0, !waiting.isEmpty else { return }
        let workerID = UUID()
        self.workerID = workerID
        worker = Task { [weak self] in
            while let self, !Task.isCancelled, self.pauseCount == 0, !self.waiting.isEmpty {
                let candidate = self.waiting.removeFirst()
                guard self.keyphrasesByDescription[candidate.modelDescription] == nil else { continue }
                let keyphrases = await Self.keyphrases(describing: candidate)
                guard !Task.isCancelled else { break }
                // The model is busy or not ready: stop, and start with this
                // tab on the next request.
                guard let keyphrases else {
                    self.waiting.insert(candidate, at: 0)
                    break
                }
                self.remember(keyphrases, for: candidate.modelDescription)
            }
            // `forgetAll` may have started a newer worker meanwhile; leave it.
            if self?.workerID == workerID { self?.worker = nil }
        }
    }

    private func remember(_ keyphrases: [String], for description: String) {
        keyphrasesByDescription[description] = keyphrases
        describedOrder.append(description)
        if describedOrder.count > Self.maximumCachedDescriptions {
            keyphrasesByDescription[describedOrder.removeFirst()] = nil
        }
    }

    /// Up to five keyphrases for `candidate`; none when the model declines,
    /// which leaves Tidy to read the tab's cleaned title instead; or nil when
    /// the model is busy or not ready, so the tab is described later.
    private static func keyphrases(describing candidate: TidyTabCandidate) async -> [String]? {
        do {
            let text = try await LanguageModelSession(
                model: SystemLanguageModel(guardrails: .permissiveContentTransformations), instructions: instructions
            )
            .respond(to: candidate.modelDescription, options: options).content
            return cleanedKeyphrases(text.split(whereSeparator: \.isNewline).map(String.init))
        } catch {
            DiagnosticLog.tidy.error("Tidy couldn't describe a tab: \(loggedName(of: error))")
            return isTemporary(error) ? nil : []
        }
    }

    /// `error` by its type and case alone, because the model's errors can
    /// quote the prompt, which holds the tab's title and address.
    private static func loggedName(of error: any Error) -> String {
        let mirror = Mirror(reflecting: error)
        guard mirror.displayStyle == .enum else { return "\(type(of: error))" }
        return "\(type(of: error)).\(mirror.children.first?.label ?? "\(error)")"
    }

    /// Whether `error` says the model is busy, rate limited or not ready, rather
    /// than that it declines this tab.
    private static func isTemporary(_ error: any Error) -> Bool {
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            if case .rateLimited? = error as? LanguageModelError { return true }
            if case .timeout? = error as? LanguageModelError { return true }
            if case .assetsUnavailable? = error as? SystemLanguageModel.Error { return true }
            if case .concurrentRequests? = error as? LanguageModelSession.Error { return true }
        }
        switch error as? LanguageModelSession.GenerationError {
        case .rateLimited?, .concurrentRequests?, .assetsUnavailable?: return true
        default: return false
        }
    }

    /// The model's lines without list marks, echoed labels such as
    /// "Shopping for:", or bare numbers. A single line of commas is split.
    private static func cleanedKeyphrases(_ lines: [String]) -> [String] {
        var phrases = lines
        if phrases.count == 1, phrases[0].contains(",") {
            phrases = phrases[0].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let cleaned = phrases.compactMap { line -> String? in
            var phrase = line
            if let colon = phrase.firstIndex(of: ":") {
                let label = phrase[..<colon]
                let rest = phrase[phrase.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty, label.split(separator: " ").count <= 6 { phrase = rest }
            }
            phrase = phrase.trimmingCharacters(in: CharacterSet(charactersIn: " .-*•\u{2014}\t"))
            return phrase.isEmpty || phrase.allSatisfy(\.isNumber) ? nil : phrase
        }
        return Array(cleaned.prefix(maximumKeyphrases))
    }
}
