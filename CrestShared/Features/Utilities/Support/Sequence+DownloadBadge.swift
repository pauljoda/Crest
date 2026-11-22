import SwiftUI

/// What a downloads badge shows for a Space's downloads, wherever it is drawn.
extension Sequence<DownloadState> {
    // MARK: - Variables

    /// How far the transferring downloads are together, to the nearest
    /// hundredth, or nil while none transfers or one does not know its size
    /// yet: what every downloads badge and the Mac's Dock tile show.
    var notificationProgress: Double? {
        let transferring = filter(\.phase.isTransferring).map(\.telemetry)
        let sizes = transferring.compactMap(\.totalBytes)
        // Summed as doubles, which sizes a server declares near the integer
        // limit cannot overflow.
        let total = sizes.reduce(0.0) { $0 + Double($1) }
        guard !transferring.isEmpty, sizes.count == transferring.count, total > 0 else { return nil }
        let received = transferring.reduce(0.0) { $0 + Double($1.bytesReceived) }
        return (received / total * 100).rounded() / 100
    }

    // MARK: - Actions - Badge

    /// The colour a downloads badge wears: danger while any download needs
    /// the person's attention, and `accent` otherwise.
    func badgeTint(otherwise accent: Color) -> Color {
        contains { $0.phase.needsAttention } ? CrestColor.danger : accent
    }
}
