import Foundation

/// The one action a notice offers. Each is its own, so two notices with the
/// same words stay two notices.
struct BrowserNoticeAction: Equatable, Hashable {
    // MARK: - Variables

    private let id = UUID()
    let title: String
    let perform: @MainActor () -> Void

    // MARK: - Initializers

    init(title: String, perform: @escaping @MainActor () -> Void) {
        self.title = title
        self.perform = perform
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserNoticeAction, rhs: BrowserNoticeAction) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
