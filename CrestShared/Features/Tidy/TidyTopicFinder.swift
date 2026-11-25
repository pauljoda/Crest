import Foundation
import FoundationModels

/// Finds the topics among a Space's loose open tabs on this device. Nothing
/// leaves it.
///
/// Most of the work happens before the person presses Tidy:
/// `TidyTabDescriptions` has Apple's on-device model describe each tab in a
/// few keyphrases in the background. Pressing Tidy embeds those keyphrases
/// with a static word-vector table and clusters them away from the main
/// actor, in milliseconds, then asks the model to name the clusters, a few at
/// a time. In a small Space, tabs whose keyphrases are likely invented, such
/// as a site's front page, are then checked one by one against the names.
@available(macOS 26, *)
struct TidyTopicFinder: Sendable {
    // MARK: - Static Variables

    /// Spaces this small are checked tab by tab after naming; larger ones
    /// would wait too long for it.
    private static let maximumVerifiedTabCount = 20

    /// The most clusters one naming call names, so a Space of many topics
    /// still fits the model's context.
    private static let maximumNamedGroupCount = 8

    /// The name the model gives a group that is general browsing, and the
    /// check's answer for a tab that fits no name.
    private static let noTopic = "none"

    /// Group names that are kinds of browsing or catch-alls rather than topics,
    /// whose groups stay loose.
    private static let looseGroupName = try! NSRegularExpression(
        pattern:
            "^(none|e-?mails?|mail|inbox|email inbox|calendars?|chat|messages?|messaging|communication"
            + "|social( media)?|music|videos?|news|.* news|general news|weather|sports?"
            + "|misc(ellaneous)?|others?|general|various|uncategori[sz]ed|browsing|websites?)$",
        options: [.caseInsensitive])
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
    private static let options = GenerationOptions(samplingMode: .greedy)

    /// The most of a title the naming prompt shows, so a Space of long titles
    /// still fits the model's context.
    private static let maximumNamedTitleLength = 80

    /// The longest Group name Tidy proposes, well inside the core's limit.
    private static let maximumGroupNameLength = 40

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

    let embedder: TidyTabEmbedder
    /// The keyphrases written for the tabs so far, by each tab's model
    /// description.
    let keyphrases: [String: [String]]

    // MARK: - Actions - Warming

    /// Loads the model ahead of a likely Tidy, which saves about a second on
    /// the first one.
    static func prewarm() {
        LanguageModelSession(model: namingModel, instructions: namingInstructions).prewarm()
    }

    // MARK: - Actions - Topics

    /// The topics among `candidates`, each holding two or more of them in
    /// sidebar order. Every other tab stays loose. Throws the model's error
    /// when naming fails.
    func topics(for candidates: [TidyTabCandidate]) async throws -> [TidyTopic] {
        // Copies of one page group as one, so they never make a Group of
        // their own, and join their page's Group together.
        let copiesByDescription = Dictionary(grouping: candidates, by: \.modelDescription)
        var seenDescriptions: Set<String> = []
        let groupable = candidates.filter {
            !$0.isLooseSiteFrontPage && seenDescriptions.insert($0.modelDescription).inserted
        }
        let texts = groupable.map { candidate in
            let phrases = self.keyphrases[candidate.modelDescription] ?? []
            return phrases.isEmpty ? candidate.cleanedTitle : phrases.joined(separator: "; ")
        }
        let embedder = embedder
        let (vectors, clusters) = await Task.detached(priority: .userInitiated) {
            let vectors = texts.map(embedder.vector(for:))
            return (vectors, TidyTabGroups(vectors: vectors).groups())
        }.value
        let groupedIndices = clusters.filter { !Self.isOnlyFrontPagesOfDifferentSites($0.map { groupable[$0] }) }
        guard !groupedIndices.isEmpty else { return [] }
        var groups = groupedIndices.map { $0.map { groupable[$0] } }
        let groupVectors = groupedIndices.map { members in
            TidyTabEmbedder.unitLength(
                members.map { vectors[$0] }.reduce(into: [Float](repeating: 0, count: vectors[0].count)) {
                    for index in $0.indices { $0[index] += $1[index] }
                })
        }
        var names: [String] = []
        for start in stride(from: 0, to: groups.count, by: Self.maximumNamedGroupCount) {
            let batch = start..<min(start + Self.maximumNamedGroupCount, groups.count)
            names += try await self.names(for: Array(groups[batch]), meaning: Array(groupVectors[batch]))
        }
        if candidates.count <= Self.maximumVerifiedTabCount {
            (groups, names) = await Self.verified(groups, names: names)
        }
        return Self.topics(groups: groups, names: names, copies: copiesByDescription, inOrderOf: candidates)
    }

    /// News, social and app home pages pair up by kind, not by anything the
    /// person is working on. An article one level down is no home page.
    private static func isOnlyFrontPagesOfDifferentSites(_ group: [TidyTabCandidate]) -> Bool {
        group.allSatisfy(\.isFrontPage) && Set(group.map(\.host)).count == group.count
    }

    /// `name` cut at a word to `maximumGroupNameLength`, or at that length
    /// when no space is in reach. The model writes a few words, but not always.
    private static func fittedName(_ name: String) -> String {
        guard name.count > maximumGroupNameLength else { return name }
        let cut = name.prefix(maximumGroupNameLength)
        guard let space = cut.lastIndex(of: " ") else { return String(cut) }
        return String(cut[..<space])
    }

    private static func isTopic(_ name: String) -> Bool {
        name.contains(where: \.isLetter)
            && looseGroupName.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) == nil
    }

    /// A topic for each group named for one, with its tabs and those tabs'
    /// `copies` in sidebar order. The core files topics named alike into one
    /// Group.
    private static func topics(
        groups: [[TidyTabCandidate]], names: [String], copies: [String: [TidyTabCandidate]],
        inOrderOf candidates: [TidyTabCandidate]
    ) -> [TidyTopic] {
        zip(groups, names.map(fittedName)).compactMap { group, name in
            guard isTopic(name) else { return nil }
            let members = Set(group.flatMap { copies[$0.modelDescription] ?? [$0] }.map(\.tabID))
            return TidyTopic(title: name, tabIDs: candidates.map(\.tabID).filter(members.contains))
        }
    }

    // MARK: - Actions - Naming

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
        let namingOptions = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 64 + 24 * groups.count)
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
            // A line with no name leaves its group to the retry.
            guard !name.isEmpty else { continue }
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
