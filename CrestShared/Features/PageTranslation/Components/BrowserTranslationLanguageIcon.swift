import SwiftUI

/// Native menus need an original-color image to retain an emoji in their icon column.
@MainActor
struct BrowserTranslationLanguageIcon: View {
    let identifier: String
    @Environment(\.displayScale) private var displayScale
    private static var images: [String: Image] = [:]

    var body: some View {
        if identifier.isEmpty {
            Image(systemName: "text.magnifyingglass")
        } else if let image = localeImage {
            image.renderingMode(.original)
        } else {
            Image(systemName: "character.bubble")
        }
    }

    private var localeImage: Image? {
        let language = Locale.Language(identifier: identifier)
        // Honor an explicit locale first; use Foundation's likely region for
        // region-neutral language identifiers supplied by Translation.
        guard
            let region =
                (Locale(identifier: identifier).region
                ?? Locale(identifier: language.maximalIdentifier).region)?.identifier,
            region.unicodeScalars.count == 2,
            region.unicodeScalars.allSatisfy({ (65...90).contains($0.value) })
        else { return nil }
        let cacheKey = "\(region)|\(displayScale)"
        if let image = Self.images[cacheKey] { return image }
        let flag = String(
            String.UnicodeScalarView(
                region.unicodeScalars.compactMap {
                    UnicodeScalar(127397 + $0.value)
                }))
        let renderer = ImageRenderer(content: Text(flag).font(.system(size: 16)).frame(width: 20, height: 20))
        renderer.scale = displayScale
        guard let cgImage = renderer.cgImage else { return nil }
        let image = Image(decorative: cgImage, scale: displayScale)
        Self.images[cacheKey] = image
        return image
    }
}
