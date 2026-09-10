import Foundation
import NaturalLanguage
import Observation
@preconcurrency import Translation
import WebKit

/// One live document owns its offer, model work, and restoration token. Nothing
/// here is persisted or shared between pages, Spaces, profiles, or private sessions.
@Observable @MainActor
final class BrowserPageTranslation {
    var sourceID = ""
    var targetID = ""
    private(set) var languages: [Locale.Language] = []
    private(set) var installedLanguageIDs: Set<String> = []
    private(set) var downloadRevision = 0
    @ObservationIgnored private var languageCheckID: String?
    @ObservationIgnored private var languageLoadTask: Task<[Locale.Language], Never>?

    var downloadedLanguages: [Locale.Language] {
        languages.filter { installedLanguageIDs.contains($0.minimalIdentifier) }
    }
    var otherLanguages: [Locale.Language] { languages.filter { !installedLanguageIDs.contains($0.minimalIdentifier) } }
    var languageStatusID: String { "\(sourceID)|\(targetID)|\(downloadRevision)" }
    private(set) var configuration: TranslationSession.Configuration?
    private(set) var documentRevision = 0
    private(set) var isOffered = false
    private(set) var isDismissed = false
    private(set) var isWorking = false
    private(set) var isTranslated = false
    private(set) var status = ""
    var showsInformation = false

    @ObservationIgnored private weak var webView: WKWebView?
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var session: TranslationSession?
    @ObservationIgnored private var hasDetected = false
    @ObservationIgnored private var automaticAttempted = false
    @ObservationIgnored private var isAutomaticOperation = false
    @ObservationIgnored private var detectedInstalledPair: String?
    @ObservationIgnored private var lastConfiguration: TranslationSession.Configuration?
    @ObservationIgnored private var restorationTask: Task<Void, Error>?
    private var translatedSourceID = ""
    private var translatedTargetID = ""

    var hasSelectedTranslation: Bool {
        isTranslated && sourceID == translatedSourceID && targetID == translatedTargetID
    }

    var showsToolbar: Bool { isOffered && !isDismissed }
    var targetName: String { languageName(targetID) }

    func languageName(_ identifier: String) -> String {
        guard !identifier.isEmpty else { return String(localized: "Detect Language") }
        return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    func setActive(_ active: Bool, in webView: WKWebView) {
        self.webView = webView
        isActive = active
        if !active { cancel() }
    }

    func detect(in webView: WKWebView) async {
        guard isActive, !hasDetected, !isWorking else { return }
        let revision = documentRevision
        do {
            for attempt in 0..<3 {
                try await Task.sleep(for: .milliseconds(attempt == 0 ? 1500 : 1000))
                guard isActive, revision == documentRevision, !isWorking, !webView.isLoading else { return }
                let sample = try await BrowserTranslationDocument.sample(in: webView)
                let detected = await Task.detached(priority: .utility) { Self.detectedLanguage(in: sample) }.value
                try Task.checkCancellation()
                guard isActive, revision == documentRevision, !isWorking else { return }
                guard let detected else { continue }
                hasDetected = true
                sourceID = detected
                let preferred = Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")
                guard preferred.languageCode != Locale.Language(identifier: detected).languageCode else { return }
                await loadLanguages()
                guard isActive, revision == documentRevision, !isWorking, !Task.isCancelled else { return }
                let detectedLanguage = Locale.Language(identifier: detected)
                sourceID =
                    languages.first { $0.minimalIdentifier == detectedLanguage.minimalIdentifier }?.minimalIdentifier
                    ?? languages.first {
                        $0.languageCode == detectedLanguage.languageCode && $0.script == detectedLanguage.script
                    }?.minimalIdentifier
                    ?? detected
                guard isActive, revision == documentRevision, !isWorking, !Task.isCancelled else { return }
                let availability = await BrowserTranslationPreference.languageAvailability().status(
                    from: .init(identifier: sourceID), to: .init(identifier: targetID))
                guard isActive, revision == documentRevision, !isWorking, !Task.isCancelled else { return }
                isOffered = availability != .unsupported
                detectedInstalledPair = availability == .installed ? "\(sourceID)|\(targetID)" : nil
                return
            }
            hasDetected = true
        } catch {
            // Detection never interrupts navigation or requests a model download.
        }
    }

    nonisolated static func detectedLanguage(in sample: BrowserTranslationDocument.Sample) -> String? {
        guard sample.text.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 8 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample.text)
        let dominant = recognizer.dominantLanguage
        let confidence = dominant.map { recognizer.languageHypotheses(withMaximum: 1)[$0, default: 0] } ?? 0
        if sample.text.count >= 80, confidence >= 0.8 { return dominant?.rawValue }
        // Search pages and other mixed-language interfaces can have a weak
        // statistical result while explicitly declaring the document language.
        let declared = Locale.Language(identifier: sample.declaredLanguage)
        if !sample.declaredLanguage.isEmpty, let code = declared.languageCode?.identifier, code != "und" {
            return declared.minimalIdentifier
        }
        return sample.text.count >= 20 && confidence >= 0.6 ? dominant?.rawValue : nil
    }

    func loadLanguages() async {
        guard languages.isEmpty else { return }
        let load =
            languageLoadTask
            ?? Task {
                let supported = await BrowserTranslationPreference.languageAvailability().supportedLanguages
                // The strategy-specific catalog can be empty even when status(from:to:)
                // confirms installed pairs. Keep the general catalog available for menus.
                return supported.isEmpty ? await LanguageAvailability().supportedLanguages : supported
            }
        languageLoadTask = load
        languages = await load.value.sorted {
            languageName($0.minimalIdentifier).localizedStandardCompare(languageName($1.minimalIdentifier))
                == .orderedAscending
        }
        languageLoadTask = nil
        guard targetID.isEmpty else { return }
        let preferred = Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")
        targetID = BrowserTranslationPreference.preferredTarget(in: languages, preferred: preferred).minimalIdentifier
    }

    func refreshInstalledLanguages(force: Bool = false) async {
        await loadLanguages()
        let check = languageStatusID
        guard force || languageCheckID != check else { return }
        languageCheckID = check
        let identifiers = languages.map(\.minimalIdentifier)
        // Apple reports installed pairs. A positive result confirms both
        // languages; unsupported/supported pairs do not prove either is absent.
        var pairs = identifiers.map { [$0, targetID] }
        if !sourceID.isEmpty { pairs += identifiers.map { [sourceID, $0] } }
        let installed = await Self.installedLanguages(in: pairs)
        guard !Task.isCancelled, check == languageStatusID else {
            if languageCheckID == check { languageCheckID = nil }
            return
        }
        installedLanguageIDs = installed
    }

    private nonisolated static func installedLanguages(in pairs: [[String]]) async -> Set<String> {
        await withTaskGroup(of: [String].self, returning: Set<String>.self) { group in
            var iterator = pairs.makeIterator()
            func enqueue(_ pair: [String]) {
                group.addTask {
                    guard !Task.isCancelled, !pair[0].isEmpty, !pair[1].isEmpty else { return [] }
                    let status = await BrowserTranslationPreference.languageAvailability().status(
                        from: .init(identifier: pair[0]), to: .init(identifier: pair[1]))
                    return status == .installed ? pair : []
                }
            }
            for _ in 0..<4 { if let pair = iterator.next() { enqueue(pair) } }
            var installed: Set<String> = []
            for await pair in group {
                installed.formUnion(pair)
                if !Task.isCancelled, let next = iterator.next() { enqueue(next) }
            }
            return installed
        }
    }

    func present() {
        isOffered = true
        isDismissed = false
        Task { await loadLanguages() }
    }

    func automaticallyTranslateIfAvailable(enabled: Bool) async {
        if !enabled, isAutomaticOperation { cancel() }
        guard enabled, isActive, hasDetected, isOffered, !isDismissed,
            !automaticAttempted, !isWorking, !isTranslated, !sourceID.isEmpty
        else { return }
        let revision = documentRevision
        let source = Locale.Language(identifier: sourceID)
        let preferred = Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")
        guard source.languageCode != preferred.languageCode else { return }
        let target = BrowserTranslationPreference.preferredTarget(in: languages, preferred: preferred)
        let confirmedPair = detectedInstalledPair == "\(sourceID)|\(target.minimalIdentifier)"
        let availability: LanguageAvailability.Status
        if confirmedPair {
            availability = .installed
        } else {
            availability = await BrowserTranslationPreference.languageAvailability().status(from: source, to: target)
        }
        guard !Task.isCancelled, isActive, revision == documentRevision,
            source == Locale.Language(identifier: sourceID), !isWorking, !isTranslated,
            !automaticAttempted, !isDismissed
        else { return }
        automaticAttempted = true
        targetID = target.minimalIdentifier
        guard availability == .installed else {
            status = String(localized: "Download languages to translate automatically. Tap Translate to continue.")
            return
        }
        #if !targetEnvironment(simulator)
            targetID = target.minimalIdentifier
            isWorking = true
            isAutomaticOperation = true
            status = String(localized: "Automatically translating to \(targetName)…")
            // This session cannot request downloads or present consent UI.
            let installedSession: TranslationSession
            if #available(iOS 26.4, macOS 26.4, *) {
                installedSession = TranslationSession(
                    installedSource: source, target: target, preferredStrategy: .lowLatency)
            } else {
                installedSession = TranslationSession(installedSource: source, target: target)
            }
            await run(using: installedSession, configuration: nil)
        #endif
    }

    func setToolbarVisible(_ visible: Bool) {
        guard visible != showsToolbar else { return }
        if visible { present() } else { dismiss() }
    }

    func toggleToolbarVisibility() {
        setToolbarVisible(!showsToolbar)
    }

    func dismiss() {
        automaticAttempted = true
        isDismissed = true
        // Hiding chrome must not cancel a running page translation.
    }

    func start() {
        guard isActive, !isWorking, !targetID.isEmpty else { return }
        automaticAttempted = true
        isAutomaticOperation = false
        isOffered = true
        isDismissed = false
        #if targetEnvironment(simulator)
            status = String(
                localized: "Apple Translation requires a physical device. It is not available in Simulator.")
            showsInformation = true
        #else
            isWorking = true
            status = String(localized: "Preparing translation…")
            var next = lastConfiguration ?? .init()
            next.source = sourceID.isEmpty ? nil : .init(identifier: sourceID)
            next.target = .init(identifier: targetID)
            if #available(iOS 26.4, macOS 26.4, *) { next.preferredStrategy = .lowLatency }
            next.invalidate()
            lastConfiguration = next
            configuration = next
        #endif
    }

    func run(using session: TranslationSession, configuration expected: TranslationSession.Configuration?) async {
        guard expected != nil || isAutomaticOperation,
            expected == configuration, isActive, isWorking, let webView
        else { return }
        let automatic = isAutomaticOperation
        self.session = session
        let revision = documentRevision
        let operation = UUID().uuidString
        token = operation
        defer {
            if token == operation {
                isWorking = false
                configuration = nil
                self.session = nil
                isAutomaticOperation = false
                downloadRevision &+= 1
            }
        }
        do {
            if automatic {
                let ready = await session.isReady
                try validate(operation, revision: revision)
                guard ready else {
                    status = String(localized: "Automatic translation is unavailable. Tap Translate to try manually.")
                    return
                }
            }
            let capture = try await BrowserTranslationDocument.capture(in: webView, token: operation)
            try validate(operation, revision: revision)
            isTranslated = false
            guard !capture.texts.isEmpty else {
                status = String(
                    localized:
                        "No supported page text was found. Editable fields, embedded pages, and images are excluded.")
                return
            }
            // Only an explicit Translate action reaches the framework's model
            // download consent UI. Auto-detection never prepares a session.
            if !automatic { try await session.prepareTranslation() }
            try validate(operation, revision: revision)
            var applied = 0
            var completed = 0
            try await Self.translate(capture.texts, using: session) { updates in
                try self.validate(operation, revision: revision)
                applied += try await BrowserTranslationDocument.apply(updates, token: operation, in: webView)
                try self.validate(operation, revision: revision)
                completed += updates.count
                self.isTranslated = applied > 0
                self.status =
                    automatic
                    ? String(localized: "Automatically translating… \(completed) of \(capture.texts.count)")
                    : String(localized: "Translating… \(completed) of \(capture.texts.count)")
            }
            translatedSourceID = sourceID
            translatedTargetID = targetID
            if capture.isLimited || applied < capture.texts.count {
                status =
                    automatic
                    ? String(
                        localized:
                            "Automatically translated available text to \(targetName). Some content was too large or changed during translation."
                    )
                    : String(
                        localized:
                            "Translated available text. Some content was too large or changed during translation.")
            } else {
                status =
                    automatic
                    ? String(localized: "Automatically translated to \(targetName)")
                    : String(localized: "Translated to \(targetName)")
            }
        } catch {
            guard token == operation, revision == documentRevision else { return }
            try? await BrowserTranslationDocument.restore(token: operation, in: webView)
            guard token == operation, revision == documentRevision else { return }
            isTranslated = false
            status =
                error is CancellationError
                ? String(localized: "Translation cancelled. Original text restored.")
                : String(localized: "Translation could not finish. \(error.localizedDescription)")
        }
    }

    // Build requests and consume responses away from the UI executor. Repeated
    // text is translated once, and the first result reaches the page immediately.
    private nonisolated static func translate(
        _ texts: [String], using session: TranslationSession,
        receive: @MainActor @Sendable ([BrowserTranslationDocument.Update]) async throws -> Void
    ) async throws {
        let indices = Dictionary(grouping: texts.indices, by: { texts[$0] })
        var seen: Set<String> = []
        let requests = texts.enumerated().compactMap { index, text -> TranslationSession.Request? in
            guard seen.insert(text).inserted else { return nil }
            return TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        var pending: [BrowserTranslationDocument.Update] = []
        var lastDelivery: ContinuousClock.Instant?
        for try await response in session.translate(batch: requests) {
            try Task.checkCancellation()
            guard let identifier = response.clientIdentifier, let index = Int(identifier), texts.indices.contains(index)
            else { continue }
            pending += (indices[texts[index]] ?? []).map { .init(index: $0, text: response.targetText) }
            let now = ContinuousClock.now
            if lastDelivery == nil || pending.count >= 8 || lastDelivery!.duration(to: now) >= .milliseconds(60) {
                try await receive(pending)
                pending.removeAll(keepingCapacity: true)
                lastDelivery = now
            }
        }
        if !pending.isEmpty { try await receive(pending) }
    }

    private func validate(_ operation: String, revision: Int) throws {
        try Task.checkCancellation()
        guard isActive, token == operation, documentRevision == revision else { throw CancellationError() }
    }

    func suspend() {
        isActive = false
        cancel()
    }

    func showOriginal() {
        automaticAttempted = true
        cancel(restoringCompleted: true)
    }

    func cancel(restoringCompleted: Bool = false) {
        guard isWorking || restoringCompleted else { return }
        session?.cancel()
        session = nil
        configuration = nil
        isWorking = false
        isAutomaticOperation = false
        let previous = token
        token = nil
        isTranslated = false
        status = String(localized: "Original page")
        if let previous, let webView {
            let revision = documentRevision
            let restoration = Task { try await BrowserTranslationDocument.restore(token: previous, in: webView) }
            restorationTask = restoration
            Task {
                do { try await restoration.value } catch {
                    guard token == nil, revision == documentRevision else { return }
                    status = String(localized: "The page could not be restored. Reload to show the original document.")
                }
            }
        }
    }

    func prepareForReaderMode() async throws {
        reset()
        try await restorationTask?.value
    }

    func documentURLDidChange(from previous: URL?, to next: URL?) {
        // In-document anchors retain their translation; a new route does not.
        guard
            previous?.absoluteString.split(separator: "#", maxSplits: 1).first
                != next?.absoluteString.split(separator: "#", maxSplits: 1).first
        else { return }
        reset()
    }

    func reset() {
        cancel(restoringCompleted: true)
        documentRevision &+= 1
        hasDetected = false
        automaticAttempted = false
        detectedInstalledPair = nil
        sourceID = ""
        isOffered = false
        isDismissed = false
        showsInformation = false
        status = ""
    }
}
