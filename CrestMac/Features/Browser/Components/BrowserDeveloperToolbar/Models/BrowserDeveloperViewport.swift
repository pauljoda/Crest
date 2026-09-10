import Foundation

/// CSS viewport presets, not hardware or user-agent emulation.
enum BrowserDeveloperViewport: Hashable, Identifiable {
    case compactPhone, phone, largePhone, desktop, wideDesktop, ultrawide
    case custom(width: Int, height: Int)

    static let presets: [Self] = [.compactPhone, .phone, .largePhone, .desktop, .wideDesktop, .ultrawide]

    static func customSize(width: String, height: String) -> Self? {
        guard let width = Int(width.trimmingCharacters(in: .whitespacesAndNewlines)),
            let height = Int(height.trimmingCharacters(in: .whitespacesAndNewlines)),
            (1...8192).contains(width), (1...8192).contains(height)
        else { return nil }
        return .custom(width: width, height: height)
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .compactPhone, .phone, .largePhone: "iphone"
        case .desktop: "laptopcomputer"
        case .wideDesktop, .ultrawide: "display"
        case .custom: "ruler"
        }
    }

    var title: String {
        switch self {
        case .compactPhone: String(localized: "Compact Phone")
        case .phone: String(localized: "Phone")
        case .largePhone: String(localized: "Large Phone")
        case .desktop: String(localized: "Desktop")
        case .wideDesktop: String(localized: "Wide Desktop")
        case .ultrawide: String(localized: "Ultrawide")
        case .custom: String(localized: "Custom")
        }
    }

    var size: CGSize {
        switch self {
        case .compactPhone: CGSize(width: 375, height: 667)
        case .phone: CGSize(width: 390, height: 844)
        case .largePhone: CGSize(width: 430, height: 932)
        case .desktop: CGSize(width: 1280, height: 800)
        case .wideDesktop: CGSize(width: 1920, height: 1080)
        case .ultrawide: CGSize(width: 2560, height: 1080)
        case .custom(let width, let height): CGSize(width: width, height: height)
        }
    }

    var dimensions: String { "\(Int(size.width)) × \(Int(size.height))" }
}

/// Preserve the CSS layout size while fitting its presentation into the Space.
/// Preview uses 100% content zoom; only its presentation scales down.
struct BrowserDeveloperViewportLayout {
    let contentSize: CGSize
    let scale: CGFloat

    init(viewport: BrowserDeveloperViewport?, available: CGSize) {
        guard let viewport else {
            contentSize = available
            scale = 1
            return
        }
        contentSize = viewport.size
        scale = max(0, min(1, available.width / contentSize.width, available.height / contentSize.height))
    }
}
