import Foundation
import FoundationModels

// MARK: - Types

/// The loose tabs of one Space waiting to be described, and whether that
/// Space may still be described: not once it locks.
private struct TidyDescriptionRequest {
    let spaceID: UUID
    var candidates: [TidyTabCandidate]
    let mayDescribe: @MainActor () -> Bool
}

/// Keyphrases Apple's on-device model writes for open tabs in the background
/// while Tidy is on, so pressing Tidy only has to group and name them.
///
/// One tab is described at a time, the Space asked for last first, and none
/// while a Tidy runs: a description beside Tidy's naming call triples the
/// wait. Keyphrases stay in memory on this device, keyed by the tab's title,
/// host and path, and are never persisted, synced or logged. A private
/// window's tabs are never described: `TabTidying` never asks. A locked
/// Space's are not either: each tab is checked against its Space's lock just
/// before it is described.
@MainActor
final class TidyTabDescriptions {
    // MARK: - Static Variables

    /// Enough for every loose tab in several busy Spaces; the oldest go first.
    private static let maximumCachedDescriptions = 1000
    private static let maximumKeyphrases = 5

    /// How long describing waits after the model was busy or not ready, and
    /// how many times in a row it waits before giving up until asked again.
    private static let retryDelay: Duration = .seconds(30)
    private static let maximumRetries = 5

    /// Five short lines with room to spare, which stops a runaway answer.
    @available(macOS 26, *)
    private static var options: GenerationOptions {
        GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 128)
    }

    private static let instructions = """
        You describe one open browser tab in five short keyphrases: what the person is working on, shopping \
        for or reading about, from specific to broad, ending with the broad project or subject it belongs to. \
        Never name the website. Write one keyphrase per line, with no numbering.
        """

    // MARK: - Variables

    private var keyphrasesByDescription: [String: [String]] = [:]
    private var describedOrder: [String] = []
    /// The Spaces whose tabs wait to be described, the one asked for last
    /// first.
    private var requests: [TidyDescriptionRequest] = []
    /// The tab being described now, as a request of its own.
    private var describing: TidyDescriptionRequest?
    private var worker: Task<Void, Never>?
    /// Which worker `worker` holds, so one that was cancelled leaves a newer
    /// one's handle alone when it ends.
    private var workerID: UUID?
    /// The wait before describing again after the model was busy.
    private var retry: Task<Void, Never>?
    private var retryCount = 0
    private var pauseCount = 0

    // MARK: - Actions - Reading

    /// The keyphrases written for `candidate`'s current title and address, or
    /// nil while it has none.
    func keyphrases(for candidate: TidyTabCandidate) -> [String]? {
        keyphrasesByDescription[candidate.modelDescription]
    }

    // MARK: - Actions - Queueing

    /// Describes each of `candidates`, the loose tabs of the Space `spaceID`,
    /// not yet described, ahead of other Spaces' tabs. They replace that
    /// Space's earlier request; none withdraws it, and stops a description of
    /// one of its tabs under way. `mayDescribe` is asked again before each
    /// tab, so a Space that locks meanwhile is described no further.
    func describe(
        _ candidates: [TidyTabCandidate], in spaceID: UUID, while mayDescribe: @escaping @MainActor () -> Bool
    ) {
        requests.removeAll { $0.spaceID == spaceID }
        let undescribed = candidates.filter { keyphrasesByDescription[$0.modelDescription] == nil }
        if !undescribed.isEmpty {
            requests.insert(
                TidyDescriptionRequest(spaceID: spaceID, candidates: undescribed, mayDescribe: mayDescribe), at: 0)
        } else if candidates.isEmpty, describing?.spaceID == spaceID {
            stopWorker()
        }
        retry?.cancel()
        retry = nil
        retryCount = 0
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
        stopWorker()
        retry?.cancel()
        retry = nil
        requests = []
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
        guard worker == nil, retry == nil, pauseCount == 0, !requests.isEmpty else { return }
        let workerID = UUID()
        self.workerID = workerID
        worker = Task { [weak self] in
            while let self, !Task.isCancelled, self.pauseCount == 0, let candidate = self.nextCandidate() {
                guard #available(macOS 26, *) else { break }
                let keyphrases = await Self.keyphrases(describing: candidate)
                guard !Task.isCancelled else { break }
                // The model is busy or not ready: put the tab back behind
                // newer requests and try again in a while.
                guard let keyphrases else {
                    self.requeue(candidate)
                    self.scheduleRetry()
                    break
                }
                self.retryCount = 0
                self.remember(keyphrases, for: candidate.modelDescription)
            }
            // `forgetAll` may have started a newer worker meanwhile; leave it.
            if self?.workerID == workerID {
                self?.worker = nil
                self?.describing = nil
            }
        }
    }

    /// The next tab to describe, from the first Space that may still be
    /// described; a Space that locked loses its request.
    private func nextCandidate() -> TidyTabCandidate? {
        describing = nil
        while let request = requests.first {
            guard request.mayDescribe(), let candidate = request.candidates.first else {
                requests.removeFirst()
                continue
            }
            requests[0].candidates.removeFirst()
            if requests[0].candidates.isEmpty { requests.removeFirst() }
            guard keyphrasesByDescription[candidate.modelDescription] == nil else { continue }
            describing = TidyDescriptionRequest(
                spaceID: request.spaceID, candidates: [candidate], mayDescribe: request.mayDescribe)
            return candidate
        }
        return nil
    }

    /// Puts `candidate`, which the model was too busy to describe, at the end
    /// of its Space's request, or after every request when its Space has none.
    private func requeue(_ candidate: TidyTabCandidate) {
        guard let describing else { return }
        if let index = requests.firstIndex(where: { $0.spaceID == describing.spaceID }) {
            if !requests[index].candidates.contains(candidate) { requests[index].candidates.append(candidate) }
        } else {
            requests.append(describing)
        }
    }

    /// Starts describing again after `retryDelay`, unless the model was busy
    /// `maximumRetries` times in a row; a new request starts it at once.
    private func scheduleRetry() {
        retryCount += 1
        guard retryCount <= Self.maximumRetries else { return }
        retry = Task { [weak self] in
            try? await Task.sleep(for: Self.retryDelay)
            guard !Task.isCancelled else { return }
            self?.retry = nil
            self?.startWorkingIfIdle()
        }
    }

    private func stopWorker() {
        worker?.cancel()
        worker = nil
        describing = nil
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
    @available(macOS 26, *)
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
    static func loggedName(of error: any Error) -> String {
        let mirror = Mirror(reflecting: error)
        guard mirror.displayStyle == .enum else { return "\(type(of: error))" }
        return "\(type(of: error)).\(mirror.children.first?.label ?? "\(error)")"
    }

    /// Whether `error` says the model is busy, rate limited or not ready, rather
    /// than that it declines this tab.
    @available(macOS 26, *)
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
