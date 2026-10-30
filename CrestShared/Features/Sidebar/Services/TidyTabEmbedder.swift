import Foundation

// MARK: - Types

/// The downloaded word-vector table is not the shape Tidy reads: a vocabulary
/// and one `F32` matrix with a row per word.
struct TidyTabEmbedderTableInvalid: Error {}

/// Turns a tab's text into a meaning vector with a static word-vector table,
/// potion-base-8M by Minish Lab: `TidyWordPieceTokenizer` splits the text into
/// word pieces, and the vector is the unit-length mean of their rows. No neural
/// network runs, so a vector costs microseconds.
struct TidyTabEmbedder: Sendable {
    // MARK: - Variables

    private let tokenizer: TidyWordPieceTokenizer
    private let dimension: Int
    /// Every row, one after another, read from the downloaded file.
    private let matrix: [Float]

    // MARK: - Initializers

    /// Reads `vocabularyURL`, one word piece per line in row order, and the
    /// safetensors file at `matrixURL`. Throws `TidyTabEmbedderTableInvalid`
    /// when they do not describe one table.
    init(vocabularyURL: URL, matrixURL: URL) throws {
        let tokenizer = try TidyWordPieceTokenizer(vocabularyURL: vocabularyURL)
        let file = try Data(contentsOf: matrixURL, options: .alwaysMapped)
        guard file.count > 8 else { throw TidyTabEmbedderTableInvalid() }
        let headerLength = Int(file.prefix(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian })
        guard file.count >= 8 + headerLength,
            let header = try JSONSerialization.jsonObject(with: file.subdata(in: 8..<(8 + headerLength)))
                as? [String: Any],
            let embeddings = header["embeddings"] as? [String: Any], embeddings["dtype"] as? String == "F32",
            let shape = embeddings["shape"] as? [Int], shape.count == 2,
            shape[0] == tokenizer.vocabularyLineCount - 1
                || shape[0] == tokenizer.vocabularyLineCount,
            let offsets = embeddings["data_offsets"] as? [Int], offsets.count == 2,
            offsets[1] - offsets[0] == shape[0] * shape[1] * MemoryLayout<Float>.size,
            file.count >= 8 + headerLength + offsets[1]
        else { throw TidyTabEmbedderTableInvalid() }
        let start = 8 + headerLength + offsets[0]
        self.matrix = file.subdata(in: start..<(start + offsets[1] - offsets[0])).withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
        self.tokenizer = tokenizer
        self.dimension = shape[1]
    }

    // MARK: - Actions - Embedding

    /// The unit-length mean of the rows of `text`'s word pieces.
    func vector(for text: String) -> [Float] {
        var sum = [Float](repeating: 0, count: dimension)
        for row in tokenizer.ids(for: text) {
            let base = row * dimension
            for index in 0..<dimension { sum[index] += matrix[base + index] }
        }
        return Self.unitLength(sum)
    }

    static func unitLength(_ vector: [Float]) -> [Float] {
        let length = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        return length > 0 ? vector.map { $0 / length } : vector
    }
}
