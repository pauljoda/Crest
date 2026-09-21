/// Ordered by severity, so an escalation is `critical > warning`. The raw
/// values are the control-plane wire vocabulary for residency policy.
enum BrowserMemoryPressureLevel: String, Comparable, Sendable {
    case warning
    case critical

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs == .warning && rhs == .critical
    }
}
