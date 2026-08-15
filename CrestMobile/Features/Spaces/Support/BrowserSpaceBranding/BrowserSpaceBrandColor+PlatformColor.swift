import SwiftUI
import UIKit

extension BrowserSpaceBrandColor {
    init(color: Color) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            self = .ocean
            return
        }
        self.init(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
    }
}
