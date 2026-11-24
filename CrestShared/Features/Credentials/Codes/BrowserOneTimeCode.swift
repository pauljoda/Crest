import Foundation

/// A one-time code the core made from a login's setup key, and when it stops
/// working. It is a secret while it lasts, so it never reaches the session.
struct BrowserOneTimeCode: Equatable, Sendable, CustomStringConvertible {
    let code: String
    let validFrom: Date
    let validUntil: Date

    /// The code in groups of three, as people read it.
    var spaced: String {
        guard code.count > 4 else { return code }
        let split = code.index(code.startIndex, offsetBy: code.count / 2)
        return "\(code[..<split]) \(code[split...])"
    }

    /// How much of its time the code has left, from 1 down to 0.
    func remaining(at now: Date) -> Double {
        let span = validUntil.timeIntervalSince(validFrom)
        guard span > 0 else { return 0 }
        return min(1, max(0, validUntil.timeIntervalSince(now) / span))
    }

    func secondsLeft(at now: Date) -> Int {
        max(0, Int(validUntil.timeIntervalSince(now).rounded(.up)))
    }

    var description: String { "BrowserOneTimeCode(code: <redacted>, validUntil: \(validUntil))" }
}
