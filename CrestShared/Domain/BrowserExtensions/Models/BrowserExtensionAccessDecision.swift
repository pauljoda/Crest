enum BrowserExtensionAccessDecision:
    String,
    CaseIterable,
    Hashable,
    Identifiable
{
    case ask
    case allow
    case block

    var id: String { rawValue }
}
