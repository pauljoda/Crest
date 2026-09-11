import SwiftUI

/// The plate's surface: the primary color, the second color where the
/// division puts it, and the finish that lights them.
struct BrowserSpaceCrestField: View {
    let division: BrowserSpaceCrestFieldDivision
    var divisionCount = BrowserSpaceCrest.defaultDivisionCount
    var finish: BrowserSpaceCrestFinish = .flat
    var sheenAngle: Double = 45
    let primaryColor: Color
    let secondaryColor: Color

    var body: some View {
        ZStack {
            primaryColor
            BrowserSpaceCrestDivisionShape(division: division, count: divisionCount)
                .fill(secondaryColor)
            finishOverlay
        }
    }

    @ViewBuilder
    private var finishOverlay: some View {
        switch finish {
        case .flat:
            EmptyView()
        case .sheen:
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.34), location: 0),
                    .init(color: .white.opacity(0.06), location: 0.5),
                    .init(color: .black.opacity(0.10), location: 1),
                ],
                startPoint: sheenPoint(direction: -1), endPoint: sheenPoint(direction: 1)
            )
        case .embossed:
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.22), location: 0),
                    .init(color: .clear, location: 0.45),
                    .init(color: .black.opacity(0.26), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
    private func sheenPoint(direction: Double) -> UnitPoint {
        let radians = sheenAngle * .pi / 180
        return UnitPoint(x: 0.5 + cos(radians) * 0.5 * direction, y: 0.5 + sin(radians) * 0.5 * direction)
    }

}
