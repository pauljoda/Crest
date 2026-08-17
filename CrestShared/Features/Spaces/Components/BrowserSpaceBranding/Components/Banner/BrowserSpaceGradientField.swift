import SwiftUI

struct BrowserSpaceGradientField: View {
    let colors: [Color]
    let angle: Double

    var body: some View {
        let axis = gradientAxis
        let gradientColors = colors.count == 1 ? [colors[0], colors[0]] : colors
        LinearGradient(
            colors: gradientColors,
            startPoint: axis.start,
            endPoint: axis.end
        )
    }

    private var gradientAxis: (start: UnitPoint, end: UnitPoint) {
        let radians = angle * .pi / 180
        let deltaX = cos(radians) * 0.5
        let deltaY = sin(radians) * 0.5
        return (
            UnitPoint(x: 0.5 - deltaX, y: 0.5 - deltaY),
            UnitPoint(x: 0.5 + deltaX, y: 0.5 + deltaY)
        )
    }
}
