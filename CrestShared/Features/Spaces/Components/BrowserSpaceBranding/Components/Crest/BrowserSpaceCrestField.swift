import SwiftUI

struct BrowserSpaceCrestField: View {
    let division: BrowserSpaceCrestFieldDivision
    let primaryColor: Color
    let secondaryColor: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            primaryColor
            switch division {
            case .plain:
                Color.clear
            case .perPale:
                HStack(spacing: 0) {
                    Color.clear
                    secondaryColor
                }
            case .perFess:
                VStack(spacing: 0) {
                    Color.clear
                    secondaryColor
                }
            case .perBend:
                LinearGradient(
                    stops: [
                        .init(color: primaryColor, location: 0),
                        .init(color: primaryColor, location: 0.49),
                        .init(color: secondaryColor, location: 0.51),
                        .init(color: secondaryColor, location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .perChevron:
                BrowserSpaceCrestChevronFieldShape()
                    .fill(secondaryColor)
            case .quarterly:
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Color.clear
                        secondaryColor
                    }
                    HStack(spacing: 0) {
                        secondaryColor
                        Color.clear
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}
