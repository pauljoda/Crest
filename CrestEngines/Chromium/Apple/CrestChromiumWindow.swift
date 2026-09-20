#if CREST_CHROMIUM_HOST
import AppKit

/// All native close routes, including accessibility and traffic-light actions,
/// pass through close(). AppKit still owns performClose and delegate checks.
@MainActor
final class CrestChromiumWindow: NSWindow {
    var approveClose: ((@escaping (Bool) -> Void) -> Void)?
    private var awaitingCloseApproval = false

    override func close() {
        guard !awaitingCloseApproval else { return }
        guard let approveClose else { super.close(); return }
        awaitingCloseApproval = true
        approveClose { [weak self] allowed in
            guard let self else { return }
            self.awaitingCloseApproval = false
            if allowed { self.closeAfterApproval() }
        }
    }

    /// Used only after the host approved this window as part of a wider batch.
    func closeAfterApproval() { super.close() }
}
#endif
