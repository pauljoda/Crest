import CoreText
import Foundation

/// The faces this process has registered, each once, from the bundle the
/// design system's resources ship in.
final class CrestDisplayFaceRegistration: @unchecked Sendable {
    // MARK: - Variables

    private let lock = NSLock()
    private var registered: [String: Bool] = [:]

    // MARK: - Actions - Registration

    func isRegistered(_ face: CrestDisplayFace) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let known = registered[face.postScriptName] { return known }
        let isRegistered = register(face)
        registered[face.postScriptName] = isRegistered
        return isRegistered
    }

    /// Registers `face` for this process, or finds it already registered,
    /// as a second window's first font does.
    private func register(_ face: CrestDisplayFace) -> Bool {
        let bundle = Bundle(for: CrestDisplayFaceRegistration.self)
        guard
            let url = bundle.url(forResource: face.fileName, withExtension: "ttf")
                ?? Bundle.main.url(forResource: face.fileName, withExtension: "ttf")
        else { return false }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        let font = CTFontCreateWithName(face.postScriptName as CFString, 12, nil)
        return CTFontCopyPostScriptName(font) as String == face.postScriptName
    }
}
