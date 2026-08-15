/// Ordered by severity, so an escalation is `critical > warning`.
enum BrowserMemoryPressureLevel: Comparable, Sendable {
    case warning
    case critical
}
