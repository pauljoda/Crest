import CoreML
import Foundation

// MARK: - Types

/// A Core ML model returned no output of the expected name.
struct TidyCoreMLOutputMissing: Error {}

/// Turns a tab's title into a meaning vector with all-MiniLM-L6-v2 converted
/// to Core ML: `TidyWordPieceTokenizer` splits the title into at most 128
/// word pieces, and the model returns their mean-pooled vector, which is
/// scaled to unit length. Predictions run off the main actor.
actor TidySentenceEmbedder {
    // MARK: - Static Variables

    private static let maximumTokenCount = 128

    // MARK: - Variables

    private let tokenizer: TidyWordPieceTokenizer
    private let model: MLModel

    // MARK: - Initializers

    /// Reads the vocabulary at `vocabularyURL` and the compiled model at
    /// `modelURL`.
    init(vocabularyURL: URL, modelURL: URL) async throws {
        tokenizer = try TidyWordPieceTokenizer(vocabularyURL: vocabularyURL)
        model = try await MLModel.load(contentsOf: modelURL, configuration: MLModelConfiguration())
    }

    // MARK: - Actions - Embedding

    /// A unit-length vector for each of `texts`, in order.
    func vectors(for texts: [String]) throws -> [[Float]] {
        try texts.map { text in
            let ids = tokenizer.modelIDs(for: text, maximumCount: Self.maximumTokenCount).map(Int32.init)
            let inputs = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLMultiArray(MLShapedArray(scalars: ids, shape: [1, ids.count])),
                "attention_mask": MLMultiArray(
                    MLShapedArray(scalars: [Int32](repeating: 1, count: ids.count), shape: [1, ids.count])),
            ])
            guard let embedding = try model.prediction(from: inputs).featureValue(for: "embedding")?.multiArrayValue
            else { throw TidyCoreMLOutputMissing() }
            return TidyTabEmbedder.unitLength(try embedding.floats())
        }
    }
}

extension MLMultiArray {
    /// Every value as a `Float`, in order, whatever type the model wrote.
    func floats() throws -> [Float] {
        try MLMultiArray(concatenating: [self], axis: 0, dataType: .float32)
            .withUnsafeBufferPointer(ofType: Float.self) { Array($0) }
    }
}
