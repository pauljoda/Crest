import Foundation
import Observation

@MainActor
@Observable
final class BrowserManualSetupModel {
    var address: String
    var placement: TabPlacement
    var errorMessage: String?

    init(
        address: String = "",
        placement: TabPlacement = .saved,
        errorMessage: String? = nil
    ) {
        self.address = address
        self.placement = placement
        self.errorMessage = errorMessage
    }

    var canAddAddress: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
