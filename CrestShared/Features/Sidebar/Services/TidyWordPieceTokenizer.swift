import Foundation

// MARK: - Types

/// The downloaded vocabulary has no `[UNK]` piece, so it is not a BERT one.
struct TidyWordPieceTokenizerInvalid: Error {}

/// Splits text into BERT's word pieces from a `vocab.txt`, as BERT's
/// uncased tokenizer does: basic normalization (drop control and format characters,
/// space out CJK, strip accents, lowercase), a split on spaces and
/// punctuation, then greedy longest-match WordPiece.
struct TidyWordPieceTokenizer: Sendable {
    // MARK: - Variables

    private let idsByPiece: [String: Int]
    private let unknownID: Int
    /// How many lines the vocabulary has, counting a blank last one.
    let vocabularyLineCount: Int

    // MARK: - Initializers

    /// Reads `url`, one word piece per line in id order.
    init(vocabularyURL url: URL) throws {
        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
        var idsByPiece: [String: Int] = [:]
        for (id, piece) in lines.enumerated() where !piece.isEmpty {
            idsByPiece[String(piece)] = id
        }
        guard let unknownID = idsByPiece["[UNK]"] else { throw TidyWordPieceTokenizerInvalid() }
        self.idsByPiece = idsByPiece
        self.unknownID = unknownID
        self.vocabularyLineCount = lines.count
    }

    // MARK: - Actions - Encoding

    /// The ids of `text`'s word pieces, with no markers around them.
    func ids(for text: String) -> [Int] {
        words(in: text).flatMap(ids(forWord:))
    }

    /// `text`'s ids between `[CLS]` and `[SEP]`, cut to `maximumCount` ids in
    /// all, as a BERT model reads one sentence.
    func modelIDs(for text: String, maximumCount: Int) -> [Int] {
        guard let start = idsByPiece["[CLS]"], let end = idsByPiece["[SEP]"] else { return [] }
        return [start] + ids(for: text).prefix(max(0, maximumCount - 2)) + [end]
    }

    private func words(in text: String) -> [String] {
        var cleaned = ""
        for scalar in text.unicodeScalars {
            if scalar.value == 0 || scalar.value == 0xFFFD
                || (Self.isOther(scalar) && !" \t\n\r".unicodeScalars.contains(scalar))
            {
                continue
            }
            if scalar.properties.isWhitespace {
                cleaned.append(" ")
            } else if Self.isCJK(scalar) {
                cleaned.append(" \(Character(scalar)) ")
            } else {
                cleaned.unicodeScalars.append(scalar)
            }
        }
        let normalized = String(
            String.UnicodeScalarView(
                cleaned.decomposedStringWithCanonicalMapping.unicodeScalars
                    .filter { $0.properties.generalCategory != .nonspacingMark })
        ).lowercased()

        var words: [String] = []
        var currentWord = ""
        for scalar in normalized.unicodeScalars {
            if scalar == " " || Self.isPunctuation(scalar) {
                if !currentWord.isEmpty { words.append(currentWord) }
                currentWord = ""
                if scalar != " " { words.append(String(scalar)) }
            } else {
                currentWord.unicodeScalars.append(scalar)
            }
        }
        if !currentWord.isEmpty { words.append(currentWord) }
        return words
    }

    private func ids(forWord word: String) -> [Int] {
        let characters = Array(word)
        guard characters.count <= 100 else { return [unknownID] }
        var ids: [Int] = []
        var start = 0
        while start < characters.count {
            var end = characters.count
            var match: Int?
            while start < end {
                let piece = (start > 0 ? "##" : "") + String(characters[start..<end])
                if let id = idsByPiece[piece] {
                    match = id
                    break
                }
                end -= 1
            }
            guard let match else { return [unknownID] }
            ids.append(match)
            start = end
        }
        return ids
    }

    /// Control, format, private-use, surrogate and unassigned characters,
    /// which BERT's tokenizer drops: a left-to-right mark, for one.
    private static func isOther(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .privateUse, .surrogate, .unassigned: true
        default: false
        }
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value)
    }

    /// ASCII symbols and Unicode punctuation, as BERT's tokenizer counts them.
    private static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if (33...47).contains(value) || (58...64).contains(value) || (91...96).contains(value)
            || (123...126).contains(value)
        {
            return true
        }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
            .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }
}
