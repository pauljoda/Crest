import Foundation
import FoundationModels

/// Tidy with Apple Intelligence. `TidyTabDescriptions` has Apple's on-device
/// model describe each tab in a few keyphrases in the background, a static
/// word-vector table embeds them, and the model is asked only once, to name
/// the groups. In a small Space, tabs whose keyphrases are likely invented,
/// such as a site's front page, are then checked one by one against the names.
@MainActor
final class AppleIntelligenceTidyModels: TidyTabModels {
    // MARK: - Static Variables

    /// Spaces this small are checked tab by tab after naming; larger ones
    /// would wait too long for it.
    private static let maximumVerifiedTabCount = 20

    /// The name the model gives a group that is general browsing, and the
    /// check's answer for a tab that fits no name.
    private static let noTopic = "none"

    private static let runTogetherNames = try! NSRegularExpression(
        pattern: "[,;|]\\s*(?=(?:group\\s*)?\\d+\\s*[:.)\u{FF1A}])", options: [.caseInsensitive])
    private static let echoedGroupLabel = try! NSRegularExpression(
        pattern: "^\\s*group\\s*\\d+\\s*[:.)\\-\u{FF1A}]\\s*", options: [.caseInsensitive])
    /// A numbered line, maybe labeled "Group", in Markdown bold, or with a
    /// full-width colon, period or a dash after the number.
    private static let nameLine = try! NSRegularExpression(
        pattern: "^[\\s*#]*(group\\s*)?(\\d+)\\s*[:.)\\-\u{2013}\u{2014}\u{FF1A}\u{FF0E}]\\s*(.+?)\\s*$",
        options: [.caseInsensitive])

    /// Always pick the likeliest answer, so the same tabs tidy the same way.
    private static let options = GenerationOptions(sampling: .greedy)

    /// The most of a title the naming prompt shows, so a Space of long titles
    /// still fits the model's context.
    private static let maximumNamedTitleLength = 80

    /// Naming reads tab titles as data to transform, which the default
    /// guardrails sometimes refuse.
    private static let namingModel = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    private static var language: String {
        let languageCode = Locale.preferredLanguages.first ?? "en"
        return Locale.current.localizedString(forLanguageCode: languageCode) ?? "English"
    }

    private static var namingInstructions: String {
        """
        You name groups of a person's open browser tabs. Each name is the subject the group's tabs have in \
        common, the way a person would label a folder for them: one to three words, never a website's name, \
        broad enough to cover every tab in the group but not a generic category such as Technology, Travel or \
        Shopping. Name a group \(noTopic) when it is email, calendars, chat, social media, music, video, news, sports or \
        weather. Write one line per group: the group number, a colon, and only the name, never the tabs. \
        Write every name in \(language), except \(noTopic).
        """
    }

    // MARK: - Variables

    private let embedder: TidyTabEmbedder

    // MARK: - Initializers

    /// Reads the word-vector table in `directory` off the main actor.
    init(directory: URL) async throws {
        embedder = try await Task.detached(priority: .utility) {
            try TidyTabEmbedder(
                vocabularyURL: directory.appendingPathComponent("vocab.txt"),
                matrixURL: directory.appendingPathComponent("model.safetensors"))
        }.value
    }

    // MARK: - Actions - Warming

    /// Loads the model ahead of a likely Tidy, which saves about a second on
    /// the first one.
    func prewarm() {
        LanguageModelSession(model: Self.namingModel, instructions: Self.namingInstructions).prewarm()
    }

    // MARK: - Actions - Embedding

    /// Each tab's keyphrases, or its cleaned title while it has none.
    func vectors(for candidates: [TidyTabCandidate]) async throws -> [[Float]] {
        candidates.map { candidate in
            let keyphrases = TidyTabDescriptions.shared.keyphrases(for: candidate) ?? []
            return embedder.vector(
                for: keyphrases.isEmpty ? candidate.cleanedTitle : keyphrases.joined(separator: "; "))
        }
    }

    // MARK: - Actions - Naming

    func named(
        _ groups: [[TidyTabCandidate]], meaning groupVectors: [[Float]], among candidates: [TidyTabCandidate]
    ) async throws -> (groups: [[TidyTabCandidate]], names: [String]) {
        let names = try await names(for: groups, meaning: groupVectors)
        guard candidates.count <= Self.maximumVerifiedTabCount else { return (groups, names) }
        return await Self.verified(groups, names: names)
    }

    /// A name for each group, from a plain-text call that sees each group's
    /// six most typical titles and hosts. A name goes to the group its number
    /// gives only when every group's number has one; otherwise the model left
    /// groups out or renumbered them, so each of its names goes to the group
    /// whose meaning vector in `groupVectors` it matches best, and the groups
    /// left unnamed get one more call. A group still without a name gets "".
    private func names(
        for groups: [[TidyTabCandidate]], meaning groupVectors: [[Float]], isRetry: Bool = false
    ) async throws -> [String] {
        let prompt = groups.enumerated().map { number, group in
            "Group \(number + 1): "
                + group.prefix(6).map { "\($0.cleanedTitle.prefix(Self.maximumNamedTitleLength)) (\($0.host))" }
                .joined(separator: "; ")
        }.joined(separator: "\n")
        // A few words a line, with room to spare: a cap that cut a name short
        // would leave its group unnamed.
        let namingOptions = GenerationOptions(sampling: .greedy, maximumResponseTokens: 64 + 24 * groups.count)
        let text = try await LanguageModelSession(model: Self.namingModel, instructions: Self.namingInstructions)
            .respond(to: prompt, options: namingOptions).content
        let lines = Self.runTogetherNames.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
        // A line labeled "Group N" names group N; otherwise the first line for
        // a number does. A later one is a numbered tab the model echoed.
        var namesByNumber: [Int: String] = [:]
        var labeledNamesByNumber: [Int: String] = [:]
        for line in lines.split(whereSeparator: \.isNewline).map(String.init) {
            guard let match = Self.nameLine.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                let numberRange = Range(match.range(at: 2), in: line), let number = Int(line[numberRange]),
                let nameRange = Range(match.range(at: 3), in: line)
            else { continue }
            let named = String(line[nameRange])
            let unlabeled = Self.echoedGroupLabel.stringByReplacingMatches(
                in: named, range: NSRange(named.startIndex..., in: named), withTemplate: "")
            let name = String(unlabeled.prefix { !":,(;\u{FF1A}\u{FF0C}\u{FF08}\u{FF1B}".contains($0) })
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"*. "))
            if namesByNumber[number] == nil { namesByNumber[number] = name }
            if match.range(at: 1).location != NSNotFound, labeledNamesByNumber[number] == nil {
                labeledNamesByNumber[number] = name
            }
        }
        namesByNumber.merge(labeledNamesByNumber) { _, labeled in labeled }
        guard !groups.indices.allSatisfy({ namesByNumber[$0 + 1] != nil }) else {
            return groups.indices.map { namesByNumber[$0 + 1] ?? "" }
        }

        let names = namesByNumber.sorted { $0.key < $1.key }.map(\.value)
        let matches = names.indices.flatMap { nameIndex in
            let nameVector = embedder.vector(for: names[nameIndex])
            return groupVectors.indices.map { groupIndex in
                (
                    name: nameIndex, group: groupIndex,
                    similarity: zip(nameVector, groupVectors[groupIndex]).reduce(0) { $0 + $1.0 * $1.1 }
                )
            }
        }.sorted { $0.similarity > $1.similarity }
        var matched = groups.map { _ in "" }
        var usedNames: Set<Int> = []
        for match in matches where !usedNames.contains(match.name) && matched[match.group].isEmpty {
            usedNames.insert(match.name)
            matched[match.group] = names[match.name]
        }
        let unnamed = groups.indices.filter { matched[$0].isEmpty }
        guard !isRetry, !unnamed.isEmpty else { return matched }
        let retried = try await self.names(
            for: unnamed.map { groups[$0] }, meaning: unnamed.map { groupVectors[$0] }, isRetry: true)
        for (index, name) in zip(unnamed, retried) { matched[index] = name }
        return matched
    }

    // MARK: - Actions - Checking

    /// Groups after checking the tabs most likely misfiled. A group named for
    /// a kind of browsing loses its front pages. In a group named for a topic,
    /// each front page or sign-in page picks among the topic names, guided, and
    /// leaves unless it picks its own group's. A refused pick keeps the tab.
    private static func verified(
        _ groups: [[TidyTabCandidate]], names: [String]
    ) async -> ([[TidyTabCandidate]], [String]) {
        let isTopic = OnDeviceTabTidyingService.isTopic
        var kept = groups
        for index in groups.indices where !names[index].isEmpty && !isTopic(names[index]) {
            kept[index].removeAll(where: \.isNearSiteRoot)
        }
        let topics = Array(Set(names.filter(isTopic))).sorted()
        let checks = groups.indices.flatMap { index in
            isTopic(names[index]) ? groups[index].filter(\.isNearSiteRoot).map { (index, $0) } : []
        }
        if !topics.isEmpty, !checks.isEmpty,
            let schema = try? GenerationSchema(
                root: DynamicGenerationSchema(name: "Topic", anyOf: topics + [noTopic]), dependencies: [])
        {
            let instructions = """
                Choose which of these topics a browser tab is about: \(topics.joined(separator: "; ")). \
                Answer "\(noTopic)" when it is about none of them.
                """
            let picks = await withTaskGroup(of: (UUID, String?).self) { taskGroup in
                for (_, candidate) in checks {
                    taskGroup.addTask {
                        let pick = try? await LanguageModelSession(instructions: instructions)
                            .respond(to: candidate.modelDescription, schema: schema, options: options)
                            .content.value(String.self)
                        return (candidate.tabID, pick)
                    }
                }
                var picks: [UUID: String] = [:]
                for await (tabID, pick) in taskGroup { picks[tabID] = pick }
                return picks
            }
            for (index, candidate) in checks {
                if let pick = picks[candidate.tabID], pick != names[index] {
                    kept[index].removeAll { $0.tabID == candidate.tabID }
                }
            }
        }
        let survivors = kept.indices.filter { kept[$0].count >= 2 }
        return (survivors.map { kept[$0] }, survivors.map { names[$0] })
    }
}
