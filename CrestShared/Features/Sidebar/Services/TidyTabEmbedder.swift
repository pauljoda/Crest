import Foundation

// MARK: - Types

/// The downloaded word-vector table is not the shape Tidy reads: a vocabulary
/// and one `F32` matrix with a row per word.
struct TidyTabEmbedderTableInvalid: Error {}

/// Turns a tab's text into a meaning vector with a static word-vector table,
/// potion-base-8M by Minish Lab: BERT's tokenizer splits the text into word
/// pieces, and the vector is the unit-length mean of their rows. No neural
/// network runs, so a vector costs microseconds.
struct TidyTabEmbedder: Sendable {
    // MARK: - Variables

    private let rowsByWordPiece: [String: Int]
    private let unknownRow: Int
    private let dimension: Int
    /// Every row, one after another, read from the downloaded file.
    private let matrix: [Float]

    // MARK: - Initializers

    /// Reads `vocabularyURL`, one word piece per line in row order, and the
    /// safetensors file at `matrixURL`. Throws `TidyTabEmbedderTableInvalid`
    /// when they do not describe one table.
    init(vocabularyURL: URL, matrixURL: URL) throws {
        let wordPieces = try String(contentsOf: vocabularyURL, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
        var rowsByWordPiece: [String: Int] = [:]
        for (row, wordPiece) in wordPieces.enumerated() where !wordPiece.isEmpty {
            rowsByWordPiece[String(wordPiece)] = row
        }
        guard let unknownRow = rowsByWordPiece["[UNK]"] else { throw TidyTabEmbedderTableInvalid() }

        let file = try Data(contentsOf: matrixURL, options: .alwaysMapped)
        guard file.count > 8 else { throw TidyTabEmbedderTableInvalid() }
        let headerLength = Int(file.prefix(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian })
        guard file.count >= 8 + headerLength,
            let header = try JSONSerialization.jsonObject(with: file.subdata(in: 8..<(8 + headerLength)))
                as? [String: Any],
            let embeddings = header["embeddings"] as? [String: Any], embeddings["dtype"] as? String == "F32",
            let shape = embeddings["shape"] as? [Int], shape.count == 2,
            shape[0] == wordPieces.count - 1
                || shape[0] == wordPieces.count,
            let offsets = embeddings["data_offsets"] as? [Int], offsets.count == 2,
            offsets[1] - offsets[0] == shape[0] * shape[1] * MemoryLayout<Float>.size,
            file.count >= 8 + headerLength + offsets[1]
        else { throw TidyTabEmbedderTableInvalid() }
        let start = 8 + headerLength + offsets[0]
        self.matrix = file.subdata(in: start..<(start + offsets[1] - offsets[0])).withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
        self.rowsByWordPiece = rowsByWordPiece
        self.unknownRow = unknownRow
        self.dimension = shape[1]
    }

    // MARK: - Actions - Embedding

    /// The unit-length mean of the rows of `text`'s word pieces.
    func vector(for text: String) -> [Float] {
        var sum = [Float](repeating: 0, count: dimension)
        for row in wordPieceRows(in: text) {
            let base = row * dimension
            for index in 0..<dimension { sum[index] += matrix[base + index] }
        }
        return Self.unitLength(sum)
    }

    static func unitLength(_ vector: [Float]) -> [Float] {
        let length = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        return length > 0 ? vector.map { $0 / length } : vector
    }

    // MARK: - Actions - Tokenizing

    /// BERT's basic normalization (drop control characters, space out CJK,
    /// strip accents, lowercase), a split on spaces and punctuation, then
    /// greedy longest-match WordPiece, as the table's tokenizer specifies.
    private func wordPieceRows(in text: String) -> [Int] {
        var cleaned = ""
        for scalar in text.unicodeScalars {
            if scalar.value == 0 || scalar.value == 0xFFFD
                || (scalar.properties.generalCategory == .control && !" \t\n\r".unicodeScalars.contains(scalar))
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
        return words.flatMap(wordPieceRows(inWord:))
    }

    private func wordPieceRows(inWord word: String) -> [Int] {
        let characters = Array(word)
        guard characters.count <= 100 else { return [unknownRow] }
        var rows: [Int] = []
        var start = 0
        while start < characters.count {
            var end = characters.count
            var match: Int?
            while start < end {
                let piece = (start > 0 ? "##" : "") + String(characters[start..<end])
                if let row = rowsByWordPiece[piece] {
                    match = row
                    break
                }
                end -= 1
            }
            guard let match else { return [unknownRow] }
            rows.append(match)
            start = end
        }
        return rows
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
