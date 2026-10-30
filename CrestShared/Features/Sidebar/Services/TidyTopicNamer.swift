import CoreML
import Foundation

/// Names a group of tabs with Mozilla's smart-tab-topic, the small T5 model
/// Firefox names tab groups with, converted to Core ML as an encoder and a
/// decoder. The name is decoded greedily, one word piece at a time, so the
/// same prompt always gets the same name. Predictions run off the main actor.
actor TidyTopicNamer {
    // MARK: - Static Variables

    /// The longest prompt the converted encoder reads.
    private static let maximumPromptTokenCount = 256
    private static let maximumNameTokenCount = 12
    /// T5 starts decoding from its padding id.
    private static let decoderStartID: Int32 = 0

    // MARK: - Variables

    private let tokenizer: TidySentencePieceTokenizer
    private let encoder: MLModel
    private let decoder: MLModel

    // MARK: - Initializers

    /// Reads the tokenizer at `tokenizerURL` and the compiled encoder and
    /// decoder.
    init(tokenizerURL: URL, encoderURL: URL, decoderURL: URL) async throws {
        tokenizer = try TidySentencePieceTokenizer(contentsOf: tokenizerURL)
        encoder = try await MLModel.load(contentsOf: encoderURL, configuration: MLModelConfiguration())
        decoder = try await MLModel.load(contentsOf: decoderURL, configuration: MLModelConfiguration())
    }

    // MARK: - Actions - Naming

    /// The model's name for `prompt`, which may be "None" or another
    /// non-topic the caller sets aside.
    func name(for prompt: String) throws -> String {
        var promptIDs = tokenizer.ids(for: prompt)
        if promptIDs.count > Self.maximumPromptTokenCount {
            promptIDs = promptIDs.prefix(Self.maximumPromptTokenCount - 1) + [tokenizer.endOfTextID]
        }
        let encoded = try encoder.prediction(
            from: MLDictionaryFeatureProvider(dictionary: [
                "input_ids": Self.row(promptIDs.map(Int32.init))
            ]))
        guard let states = encoded.featureValue(for: "encoder_states")?.multiArrayValue else {
            throw TidyCoreMLOutputMissing()
        }
        let encoderStates = try MLMultiArray(concatenating: [states], axis: 0, dataType: .float32)
        var nameIDs = [Self.decoderStartID]
        for _ in 0..<Self.maximumNameTokenCount {
            let decoded = try decoder.prediction(
                from: MLDictionaryFeatureProvider(dictionary: [
                    "decoder_ids": Self.row(nameIDs), "encoder_states": encoderStates,
                ]))
            guard let logits = try decoded.featureValue(for: "logits")?.multiArrayValue?.floats(),
                let next = logits.indices.max(by: { logits[$0] < logits[$1] })
            else { throw TidyCoreMLOutputMissing() }
            if next == tokenizer.endOfTextID { break }
            nameIDs.append(Int32(next))
        }
        return tokenizer.text(for: nameIDs.dropFirst().map(Int.init))
    }

    private static func row(_ ids: [Int32]) -> MLMultiArray {
        MLMultiArray(MLShapedArray(scalars: ids, shape: [1, ids.count]))
    }
}
