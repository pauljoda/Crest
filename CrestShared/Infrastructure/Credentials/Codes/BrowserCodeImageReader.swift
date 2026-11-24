import CoreGraphics
import Vision

/// Finds the QR codes in a picture: a snapshot of the page the person is
/// setting up a code on, or an image they chose. What a code says is handed
/// to the core, which decides whether it sets up a one-time code.
enum BrowserCodeImageReader {
    // MARK: - Actions - Reading

    /// What each QR code in `image` says, most prominent first.
    static func payloads(in image: CGImage) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            guard (try? handler.perform([request])) != nil else { return [] }
            return (request.results ?? [])
                .sorted { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height }
                .compactMap(\.payloadStringValue)
        }.value
    }
}
