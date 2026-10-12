import SwiftUI

/// One source of a crest's emblem in the studio: the controls that edit it,
/// the charge its fields make, and what it takes back from a charge.
/// `CrestChargeKind.studioSource` names each kind's source, so a kind the core
/// adds fails to compile until the studio offers a source for it.
@MainActor
protocol BrowserCrestStudioEmblemSource {
    /// The controls below the source picker.
    func controls(in emblem: BrowserCrestStudioEmblem) -> AnyView

    /// The charge the emblem's fields make for this source.
    func charge(in emblem: BrowserCrestStudioEmblem) -> CrestCharge

    /// Takes the fields this source edits from `charge`.
    func load(_ charge: CrestCharge, into emblem: BrowserCrestStudioEmblem)
}
