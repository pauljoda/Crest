import SwiftUI

/// A Space as a banner hung from a rod: its sidebar field as the cloth, its
/// icon in the middle and its name under it, the cloth coming to a point.
struct BrowserOnboardingBanner: View {
    let space: SpaceModel
    var width: CGFloat = 300
    var height: CGFloat = 600

    private var iconSize: CGFloat { width * 0.5 }

    var body: some View {
        VStack(spacing: 0) {
            rod
            cloth
                .padding(.top, -2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Banner of \(space.settings.name)")
    }

    private var rod: some View {
        Capsule()
            .fill(CrestBrandPalette.paper)
            .frame(width: width + 100, height: 10)
            .overlay {
                HStack {
                    knob
                    Spacer()
                    knob
                }
                .padding(.horizontal, -8)
            }
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }

    private var knob: some View {
        Circle().fill(CrestBrandPalette.butter).frame(width: 18, height: 18)
    }

    private var cloth: some View {
        ZStack {
            BrowserSpaceBannerBackground(branding: space.settings.look)
            VStack(spacing: 0) {
                pins
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                Spacer()
                BrowserSpaceIdentityIcon(space: space, size: iconSize)
                    .frame(width: iconSize, height: iconSize)
                Text(space.settings.name)
                    .font(CrestTypography.display(width * 0.09))
                    .foregroundStyle(CrestBrandTheme.textDisplay)
                    .lineLimit(1)
                    .padding(.top, 22)
                Spacer()
                Spacer()
            }
        }
        .frame(width: width, height: height)
        .clipShape(BrowserOnboardingPennant())
        .shadow(color: .black.opacity(0.45), radius: 30, y: 18)
        .environment(\.colorScheme, space.settings.look.foregroundTone.colorScheme)
    }

    /// The pinned tabs a sidebar holds at its top, as tiles.
    private var pins: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CrestBrandPalette.paper.opacity(0.12))
                    .frame(height: width * 0.14)
            }
        }
    }
}

/// A banner's cloth: square at the rod, coming to a point at the bottom.
private struct BrowserOnboardingPennant: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.88))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY * 0.88))
        path.closeSubpath()
        return path
    }
}
