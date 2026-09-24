extension TabIconMode {
    // MARK: - Actions - Inference

    /// The mode of a tab written before modes were stored, or whose stored
    /// term this build cannot name, taken from its own symbol: the mode whose
    /// inference prefix the symbol carries, the longest one winning, as the
    /// core decides it.
    ///
    /// TRANSITIONAL: this repeats the core's `TabIconMode.Inferred` only
    /// because the Swift session copy still decodes tabs itself. It is deleted
    /// when that copy retires and tabs arrive from the core carrying their mode.
    static func inferred(from symbol: String) -> TabIconMode {
        let claiming = all.filter { mode in
            guard let prefix = mode.inferencePrefix else { return false }
            return prefix.isEmpty || (symbol.count > prefix.count && symbol.hasPrefix(prefix))
        }
        let longest = claiming.max { ($0.inferencePrefix?.count ?? 0) < ($1.inferencePrefix?.count ?? 0) }
        guard let mode = longest else {
            preconditionFailure("A mode with an empty inference prefix claims every symbol.")
        }
        return mode
    }
}
