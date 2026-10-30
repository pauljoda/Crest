import Foundation

// MARK: - Types

/// The downloaded `tokenizer.json` is not a SentencePiece unigram vocabulary.
struct TidySentencePieceTokenizerInvalid: Error {}

/// Splits text into the word pieces of a SentencePiece unigram model, as the
/// Hugging Face `tokenizers` library does for T5, from the model's
/// `tokenizer.json`: NFKC without format characters, line breaks as spaces,
/// runs of spaces as one, a "▁" before each word, then the most likely split
/// of each word by the pieces' scores.
struct TidySentencePieceTokenizer: Sendable {
    // MARK: - Static Variables

    /// The word-boundary mark SentencePiece writes in place of a space.
    private static let boundary: Character = "\u{2581}"

    // MARK: - Variables

    private let idsByPiece: [String: Int]
    private let scores: [Float]
    private let pieces: [String]
    private let unknownID: Int
    private let unknownScore: Float
    private let longestPiece: Int
    /// Ids that decoding leaves out: padding, end of text and unknown.
    private let specialIDs: Set<Int>
    let endOfTextID: Int

    // MARK: - Initializers

    /// Reads the `model` of a `tokenizer.json` whose type is `Unigram`.
    init(contentsOf url: URL) throws {
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
            let model = root["model"] as? [String: Any], model["type"] as? String == "Unigram",
            let vocabulary = model["vocab"] as? [[Any]], let unknownID = model["unk_id"] as? Int,
            vocabulary.indices.contains(unknownID)
        else { throw TidySentencePieceTokenizerInvalid() }
        var idsByPiece: [String: Int] = [:]
        var scores: [Float] = []
        var pieces: [String] = []
        for (id, entry) in vocabulary.enumerated() {
            guard entry.count == 2, let piece = entry[0] as? String, let score = entry[1] as? Double else {
                throw TidySentencePieceTokenizerInvalid()
            }
            idsByPiece[piece] = id
            scores.append(Float(score))
            pieces.append(piece)
        }
        let specials = (root["added_tokens"] as? [[String: Any]] ?? [])
            .filter { $0["special"] as? Bool == true }
        guard let endOfTextID = specials.first(where: { $0["content"] as? String == "</s>" })?["id"] as? Int else {
            throw TidySentencePieceTokenizerInvalid()
        }
        self.idsByPiece = idsByPiece
        self.scores = scores
        self.pieces = pieces
        self.unknownID = unknownID
        // As `tokenizers` scores a character no piece covers.
        self.unknownScore = (scores.min() ?? 0) - 10
        self.longestPiece = pieces.map(\.count).max() ?? 1
        self.specialIDs = Set(specials.compactMap { $0["id"] as? Int })
        self.endOfTextID = endOfTextID
    }

    // MARK: - Actions - Encoding

    /// The ids of `text`, ending with the end-of-text id.
    func ids(for text: String) -> [Int] {
        let words = Self.normalized(text).split(separator: " ")
        return words.flatMap { ids(forWord: String(Self.boundary) + $0) } + [endOfTextID]
    }

    /// The likeliest split of `word` into pieces, by Viterbi over the pieces'
    /// scores. Characters no piece covers become one unknown id per run.
    private func ids(forWord word: String) -> [Int] {
        let characters = Array(word)
        var best = [(score: Float, start: Int, id: Int)](
            repeating: (-.infinity, 0, unknownID), count: characters.count + 1)
        best[0].score = 0
        for end in 1...characters.count {
            for start in max(0, end - longestPiece)..<end where best[start].score > -.infinity {
                guard let id = idsByPiece[String(characters[start..<end])] else { continue }
                let score = best[start].score + scores[id]
                if score > best[end].score { best[end] = (score, start, id) }
            }
            if best[end].score == -.infinity, best[end - 1].score > -.infinity {
                best[end] = (best[end - 1].score + unknownScore, end - 1, unknownID)
            }
        }
        var ids: [Int] = []
        var end = characters.count
        while end > 0 {
            let step = best[end]
            if !(step.id == unknownID && ids.last == unknownID) { ids.append(step.id) }
            end = step.start
        }
        return ids.reversed()
    }

    /// NFKC without format characters such as a left-to-right mark, with
    /// control characters and every kind of space or line break as a plain
    /// space, and runs of spaces as one, trimmed.
    private static func normalized(_ text: String) -> String {
        var spaced = ""
        for scalar in text.precomposedStringWithCompatibilityMapping.unicodeScalars {
            if scalar.properties.isWhitespace || scalar.properties.generalCategory == .control {
                if spaced.last != " " { spaced.append(" ") }
            } else if scalar.properties.generalCategory == .format {
                continue
            } else {
                spaced.unicodeScalars.append(scalar)
            }
        }
        return spaced.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Actions - Decoding

    /// The text `ids` spell, without padding, end of text or unknown pieces.
    func text(for ids: [Int]) -> String {
        ids.filter { pieces.indices.contains($0) && !specialIDs.contains($0) }
            .map { pieces[$0] }.joined()
            .replacingOccurrences(of: String(Self.boundary), with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
