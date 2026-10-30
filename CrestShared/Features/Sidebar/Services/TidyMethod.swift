import Foundation
import FoundationModels

// MARK: - Types

/// The models one way of tidying runs: how it reads each tab as a meaning
/// vector, and how it names the groups those vectors form.
@MainActor
protocol TidyTabModels: AnyObject {
    /// A meaning vector for each of `candidates`, in order.
    func vectors(for candidates: [TidyTabCandidate]) async throws -> [[Float]]

    /// `groups` with a name for each, as `TidyTabGroups` found them among
    /// `candidates`, each with its mean vector in `groupVectors`. A group may be
    /// dropped or lose tabs; a name that is not a topic leaves its group loose.
    func named(
        _ groups: [[TidyTabCandidate]], meaning groupVectors: [[Float]], among candidates: [TidyTabCandidate]
    ) async throws -> (groups: [[TidyTabCandidate]], names: [String])

    /// Loads what a likely Tidy will need first.
    func prewarm()
}

/// One way Tidy can run on this device, with the files it downloads and how
/// it behaves. Apple Intelligence is used where it is available, and open
/// models downloaded once everywhere else.
struct TidyMethod: Sendable, Equatable {
    // MARK: - Static Variables

    /// Apple's on-device model describes tabs in the background and names the
    /// groups; a static word-vector table, potion-base-8M by Minish Lab (MIT),
    /// embeds the descriptions.
    static let appleIntelligence = TidyMethod(
        directoryName: "potion-base-8M",
        files: [
            TidyModelFile(
                path: "vocab.txt", address: potion("vocab.txt"),
                sha256: "1394523a67ddd404a825428018c0582a6998bcfa044ecbcbf1f4d71adb94c61c"),
            TidyModelFile(
                path: "model.safetensors", address: potion("model.safetensors"),
                sha256: "f65d0f325faadc1e121c319e2faa41170d3fa07d8c89abd48ca5358d9a223de2"),
        ],
        centersVectors: true,
        cutHeights: heights(from: 0.60, through: 1.00),
        asksBeforeFiling: false,
        describesInBackground: true,
        summary:
            "Groups open tabs under headers using Apple Intelligence on this device. Turning it on downloads a 30 MB word list. Tab titles and addresses never leave this device.",
        downloading: "Downloading Tidy's word list…",
        downloadFailed: "Couldn't download Tidy's word list. Turn Tidy off and on to try again.",
        load: { directory in try await AppleIntelligenceTidyModels(directory: directory) })

    /// all-MiniLM-L6-v2 (Apache-2.0) embeds tab titles and Mozilla's
    /// smart-tab-topic (MPL-2.0), Firefox's tab-group namer, names the groups,
    /// both converted to Core ML and published with Crest's releases. Groups
    /// are shown for review before they are filed.
    static let openModels = TidyMethod(
        directoryName: "open-models-1",
        files: [
            TidyModelFile(
                path: "vocab.txt",
                address: URL(
                    string:
                        "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/1110a243fdf4706b3f48f1d95db1a4f5529b4d41/vocab.txt"
                )!,
                sha256: "07eced375cec144d27c900241f3e339478dec958f92fddbc551f295c992038a3"),
            TidyModelFile(
                path: "tokenizer.json",
                address: URL(
                    string:
                        "https://huggingface.co/Mozilla/smart-tab-topic/resolve/91a6ebc0318de964b0e318c89ba01514746aadb8/tokenizer.json"
                )!,
                sha256: "f5dfec163765e18e270537fe896c49f5fad74db1525641d9b255a3008b999596"),
        ]
            + coreMLPackage(
                "MiniLM",
                manifest: "97fc5c40fd4caf4c1728c5af31b49001ba3c8a1ee87fb556e821861e9ec77720",
                model: "79ea01f86a8ac79fe6b512c7d26dc11999e4e1ae21adfca322fc8ee49cedf403",
                weights: "07fcd8cab6507dc1c0322a5c87fb9fe131cf32f61a31271ee342637cb409fb1e")
            + coreMLPackage(
                "TopicEncoder",
                manifest: "1505cd1e924830a136a55271aa6f8b0ab6fae8105ea315891475f3f2e1c5817e",
                model: "3cc5e91eb32570a3a9ffd7323308b117f5073015f8c308d2d522a4be02eb4488",
                weights: "d509612cd67e27fdb749350fc7a849a3f3a5154a74a1f48ad92810d016e4d2e2")
            + coreMLPackage(
                "TopicDecoder",
                manifest: "67e64970604a9af14651aa5a7bdd228977e0ad20e1a1fb7b1fe6ee17b247bf6a",
                model: "d2c9b14f2d8536721051aeff690b8ce2b56fef6a28e1477d68b54118bf786d20",
                weights: "1c265416e9c48efdffff3fcfe994121dc5365f8511539b4d41d6bff062734b26"),
        centersVectors: false,
        cutHeights: heights(from: 0.40, through: 0.90),
        asksBeforeFiling: true,
        describesInBackground: false,
        summary:
            "Groups open tabs under headers using open models on this device, and shows the groups before filing them. Turning it on downloads 50 MB of models. Tab titles and addresses never leave this device.",
        downloading: "Downloading Tidy's models…",
        downloadFailed: "Couldn't download Tidy's models. Turn Tidy off and on to try again.",
        load: { directory in try await OpenTidyModels(directory: directory) })

    /// Where Crest publishes the converted models: a release of the
    /// repository, as with the Chromium engine.
    private static let openModelsRelease = "https://github.com/karbassi/Crest/releases/download/tidy-models-1/"

    /// The method this device runs now. Apple Intelligence that is still
    /// downloading its model counts as available, so the device doesn't fetch
    /// open models it will soon stop using.
    static var current: TidyMethod {
        switch SystemLanguageModel.default.availability {
        case .available, .unavailable(.modelNotReady): .appleIntelligence
        default: .openModels
        }
    }

    // MARK: - Variables

    /// The folder its files are kept in, under Tidy's own.
    let directoryName: String
    let files: [TidyModelFile]
    /// Grouping centers the vectors on their mean before measuring them.
    let centersVectors: Bool
    /// The cosine distances grouping may cut at, choosing by silhouette.
    let cutHeights: [Float]
    /// Tidy shows the groups and files them only once the person applies them.
    let asksBeforeFiling: Bool
    /// Tabs are described while the person browses, ahead of a Tidy.
    let describesInBackground: Bool
    let summary: LocalizedStringResource
    let downloading: LocalizedStringResource
    let downloadFailed: LocalizedStringResource
    /// Loads the models from the downloaded and verified files in a folder.
    let load: @MainActor @Sendable (URL) async throws -> any TidyTabModels

    // MARK: - Actions - Comparing

    static func == (lhs: TidyMethod, rhs: TidyMethod) -> Bool {
        lhs.directoryName == rhs.directoryName
    }

    // MARK: - Actions - Describing files

    private static func potion(_ fileName: String) -> URL {
        URL(
            string:
                "https://huggingface.co/minishlab/potion-base-8M/resolve/bf8b056651a2c21b8d2565580b8569da283cab23/\(fileName)"
        )!
    }

    /// The three files of a Core ML package, published flat as
    /// `<name>-<file>` and laid back out as `<name>.mlpackage`.
    private static func coreMLPackage(
        _ name: String, manifest: String, model: String, weights: String
    ) -> [TidyModelFile] {
        [
            ("Manifest.json", "Manifest.json", manifest),
            ("Data/com.apple.CoreML/model.mlmodel", "model.mlmodel", model),
            ("Data/com.apple.CoreML/weights/weight.bin", "weight.bin", weights),
        ].map { path, published, sha256 in
            TidyModelFile(
                path: "\(name).mlpackage/\(path)", address: URL(string: openModelsRelease + "\(name)-\(published)")!,
                sha256: sha256)
        }
    }

    private static func heights(from lowest: Float, through highest: Float) -> [Float] {
        stride(from: 0, through: Int(((highest - lowest) / 0.05).rounded()), by: 1).map { lowest + Float($0) * 0.05 }
    }
}
