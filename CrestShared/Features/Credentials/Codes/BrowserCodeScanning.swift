import SwiftUI

/// What a shell lets Set Up Code look through: the page of a site open in a
/// Space, and on iPhone and iPad the camera.
struct BrowserCodeScanning {
    /// A snapshot of a page in the Space that is open on the site, or nil
    /// when none is.
    var scanPage: ((UUID, CredentialOrigin) async -> CGImage?)?
    /// Scans a QR code with the camera, answering what it says, or nil when
    /// the person cancels.
    var scanWithCamera: (() async -> String?)?
}

extension EnvironmentValues {
    @Entry var browserCodeScanning = BrowserCodeScanning()
}
