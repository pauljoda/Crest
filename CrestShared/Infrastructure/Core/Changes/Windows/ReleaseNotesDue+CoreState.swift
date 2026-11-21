import Foundation

extension ReleaseNotesDue {
    /// The window that took the notes opens them; the read model keeps nothing.
    @MainActor func apply(to state: CoreState) {}
}
