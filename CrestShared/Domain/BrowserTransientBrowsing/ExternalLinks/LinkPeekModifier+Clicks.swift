extension LinkPeekModifier {
    // MARK: - Actions - Clicks

    /// Whether a click with `held` keys asks for a new tab: the new-tab key
    /// without the Peek key, which wins when both are held.
    func opensNewTab(holding held: ShortcutModifiers) -> Bool {
        held.contains(newTabKey) && !held.contains(peekKey)
    }
}
