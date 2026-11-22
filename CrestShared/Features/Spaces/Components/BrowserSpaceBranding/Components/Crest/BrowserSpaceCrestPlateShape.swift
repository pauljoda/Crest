import SwiftUI

/// The outline of a crest's plate, drawn as a path so it stays crisp at any
/// size and can be stroked, inset, and scaled — none of which a glyph mask
/// allowed.
struct BrowserSpaceCrestPlateShape: Shape {
    let backplate: CrestBackplate
    /// Scallops on a seal. Ignored by every other plate.
    var scallops = 14

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        switch backplate.kind {
        case .none:
            break
        case .circle:
            path.addEllipse(in: rect)
        case .oval:
            path.addEllipse(in: rect.insetBy(dx: w * 0.11, dy: 0))
        case .shield:
            path.move(to: point(0.06, 0.08))
            path.addLine(to: point(0.94, 0.08))
            path.addLine(to: point(0.94, 0.46))
            path.addQuadCurve(to: point(0.5, 0.98), control: point(0.94, 0.86))
            path.addQuadCurve(to: point(0.06, 0.46), control: point(0.06, 0.86))
            path.closeSubpath()
        case .frenchShield:
            path.move(to: point(0.08, 0.04))
            path.addLine(to: point(0.92, 0.04))
            path.addLine(to: point(0.92, 0.70))
            path.addQuadCurve(to: point(0.5, 0.97), control: point(0.92, 0.97))
            path.addQuadCurve(to: point(0.08, 0.70), control: point(0.08, 0.97))
            path.closeSubpath()
        case .diamond:
            path.move(to: point(0.5, 0.02))
            path.addLine(to: point(0.96, 0.5))
            path.addLine(to: point(0.5, 0.98))
            path.addLine(to: point(0.04, 0.5))
            path.closeSubpath()
        case .hexagon:
            path.addPath(Self.polygon(sides: 6, in: rect, rotation: -.pi / 2))
        case .octagon:
            path.addPath(Self.polygon(sides: 8, in: rect, rotation: .pi / 8))
        case .roundedSquare:
            path.addRoundedRect(
                in: rect.insetBy(dx: w * 0.05, dy: h * 0.05),
                cornerSize: CGSize(width: w * 0.22, height: h * 0.22),
                style: .continuous)
        case .seal:
            path.addPath(Self.scalloped(in: rect, scallops: max(6, scallops)))
        case .banner:
            path.move(to: point(0.12, 0.04))
            path.addLine(to: point(0.88, 0.04))
            path.addLine(to: point(0.88, 0.76))
            path.addLine(to: point(0.5, 0.97))
            path.addLine(to: point(0.12, 0.76))
            path.closeSubpath()
        case .softShield, .softHexagon, .ribbon:
            path.addPath(Self.kitPath(backplate.kind, in: rect))
        case .badge:
            let center = point(0.5, 0.44)
            let radius = w * 0.44
            path.addArc(
                center: center, radius: radius, startAngle: .degrees(160), endAngle: .degrees(20), clockwise: false)
            path.addLine(to: point(0.5, 0.98))
            path.closeSubpath()
        }
        return path
    }

    /// A soft shape as Crest's brand kit draws it on its 64-unit grid, where
    /// the plate spans 7 to 57, mapped onto `rect`.
    static func kitPath(_ kind: CrestBackplate.Kinds, in rect: CGRect) -> Path {
        let outline: String
        switch kind {
        case .softShield:
            outline = "M16 12H48Q52 12 52 16V31C52 44 43 51 32 55C21 51 12 44 12 31V16Q12 12 16 12Z"
        case .softHexagon:
            outline =
                "M27.67 11.49Q32 9 36.33 11.49L47.67 18.01Q52 20.5 52 25.5L52 38.5Q52 43.5 47.67 45.99L36.33 52.51Q32 55 "
                + "27.67 52.51L16.33 45.99Q12 43.5 12 38.5L12 25.5Q12 20.5 16.33 18.01Z"
        default:
            outline =
                "M14 15Q14 10 19 10L45 10Q50 10 50 15L50 49Q50 54 45.63 51.57L36.37 46.43Q32 44 27.63 46.43L18.37 "
                + "51.57Q14 54 14 49Z"
        }
        return BrowserSpaceCrestKitOutline(outline).path(in: rect)
    }

    static func polygon(sides: Int, in rect: CGRect, rotation: CGFloat) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<sides {
            let angle = rotation + CGFloat(index) / CGFloat(sides) * 2 * .pi
            let vertex = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if index == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
        }
        path.closeSubpath()
        return path
    }

    static func scalloped(in rect: CGRect, scallops: Int) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.9
        var path = Path()
        for index in 0..<scallops {
            let start = CGFloat(index) / CGFloat(scallops) * 2 * .pi - .pi / 2
            let end = CGFloat(index + 1) / CGFloat(scallops) * 2 * .pi - .pi / 2
            let mid = (start + end) / 2
            let valley = CGPoint(x: center.x + cos(start) * inner, y: center.y + sin(start) * inner)
            let nextValley = CGPoint(x: center.x + cos(end) * inner, y: center.y + sin(end) * inner)
            let control = CGPoint(x: center.x + cos(mid) * outer * 1.08, y: center.y + sin(mid) * outer * 1.08)
            if index == 0 { path.move(to: valley) }
            path.addQuadCurve(to: nextValley, control: control)
        }
        path.closeSubpath()
        return path
    }
}

/// An outline in Crest's brand kit's own words: absolute moves, lines, and
/// quadratic and cubic curves on its 64-unit grid, where a crest's plate
/// spans 7 to 57.
struct BrowserSpaceCrestKitOutline {
    // MARK: - Variables

    private let outline: String

    // MARK: - Initializers

    init(_ outline: String) {
        self.outline = outline
    }

    // MARK: - Actions - Drawing

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + (x - BrowserSpaceCrestKitOutlineMetrics.origin) / BrowserSpaceCrestKitOutlineMetrics.span
                    * rect.width,
                y: rect.minY + (y - BrowserSpaceCrestKitOutlineMetrics.origin) / BrowserSpaceCrestKitOutlineMetrics.span
                    * rect.height)
        }
        var path = Path()
        var numbers: [CGFloat] = []
        var command: Character = "M"
        var current = CGPoint.zero
        func flush() {
            switch command {
            case "M":
                guard numbers.count >= 2 else { return }
                current = CGPoint(x: numbers[0], y: numbers[1])
                path.move(to: point(current.x, current.y))
            case "L":
                guard numbers.count >= 2 else { return }
                current = CGPoint(x: numbers[0], y: numbers[1])
                path.addLine(to: point(current.x, current.y))
            case "H":
                guard let x = numbers.first else { return }
                current.x = x
                path.addLine(to: point(current.x, current.y))
            case "V":
                guard let y = numbers.first else { return }
                current.y = y
                path.addLine(to: point(current.x, current.y))
            case "Q":
                guard numbers.count >= 4 else { return }
                current = CGPoint(x: numbers[2], y: numbers[3])
                path.addQuadCurve(to: point(current.x, current.y), control: point(numbers[0], numbers[1]))
            case "C":
                guard numbers.count >= 6 else { return }
                current = CGPoint(x: numbers[4], y: numbers[5])
                path.addCurve(
                    to: point(current.x, current.y), control1: point(numbers[0], numbers[1]),
                    control2: point(numbers[2], numbers[3]))
            case "Z":
                path.closeSubpath()
            default:
                break
            }
            numbers = []
        }
        var token = ""
        func endNumber() {
            if let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }
        for character in outline {
            if character.isLetter {
                endNumber()
                flush()
                command = character
                if character == "Z" { flush() }
            } else if character == " " || character == "," {
                endNumber()
            } else if character == "-", !token.isEmpty {
                endNumber()
                token = "-"
            } else {
                token.append(character)
            }
        }
        endNumber()
        flush()
        return path
    }
}

enum BrowserSpaceCrestKitOutlineMetrics {
    /// Where a crest's plate starts on the kit's grid, and how far it spans.
    static let origin: CGFloat = 7
    static let span: CGFloat = 50
}
