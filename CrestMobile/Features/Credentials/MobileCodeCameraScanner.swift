import UIKit
import VisionKit

/// The camera, looking for a setup QR code, for setting up a one-time code on
/// iPhone and iPad. It covers the screen with Cancel, answers the first code
/// it reads, and goes.
@MainActor
enum MobileCodeCameraScanner {
    // MARK: - Variables

    /// Whether this device has a camera the scanner can use.
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    // MARK: - Actions - Scanning

    /// What the first QR code the camera reads says, or nil when the person
    /// cancels or there is nowhere to show the camera.
    static func scan() async -> String? {
        guard
            let presenter = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        else { return nil }
        var top = presenter
        while let presented = top.presentedViewController { top = presented }
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, isHighlightingEnabled: true)
        return await withCheckedContinuation { continuation in
            let delegate = Delegate { payload in
                scanner.stopScanning()
                scanner.dismiss(animated: true)
                continuation.resume(returning: payload)
            }
            scanner.delegate = delegate
            scanner.title = String(localized: "Scan QR Code")
            scanner.navigationItem.leftBarButtonItem = UIBarButtonItem(
                systemItem: .cancel, primaryAction: UIAction { _ in delegate.finish(nil) })
            // The delegate lives as long as the scanner on screen.
            objc_setAssociatedObject(scanner, &Delegate.key, delegate, .OBJC_ASSOCIATION_RETAIN)
            let navigation = UINavigationController(rootViewController: scanner)
            navigation.modalPresentationStyle = .fullScreen
            top.present(navigation, animated: true) { try? scanner.startScanning() }
        }
    }

    // MARK: - Types

    /// Answers once: with the first QR code the camera reads, or nil on Cancel.
    private final class Delegate: NSObject, DataScannerViewControllerDelegate {
        nonisolated(unsafe) static var key = 0
        private var answer: ((String?) -> Void)?

        init(answer: @escaping (String?) -> Void) {
            self.answer = answer
        }

        func finish(_ payload: String?) {
            answer?(payload)
            answer = nil
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]
        ) {
            for case .barcode(let barcode) in addedItems {
                guard let payload = barcode.payloadStringValue else { continue }
                finish(payload)
                return
            }
        }
    }
}
