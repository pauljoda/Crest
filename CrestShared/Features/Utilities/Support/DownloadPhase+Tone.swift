import Foundation

extension DownloadPhase {
    // MARK: - Variables

    /// How the phase reads: a decision the person owes is a warning, trouble
    /// is danger, and anything else has no tone and stays quiet.
    var tone: CrestStatusTone? {
        if awaitsDecision { return .warning }
        return needsAttention ? .danger : nil
    }
}
