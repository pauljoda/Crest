/// Whether a sidebar row is the place its page grows out of.
///
/// One rule for both ends of the pairing: the row that claims the identity and
/// the surface that zooms from it have to agree, and a start page has nothing
/// to grow into — its content is already the thing the row would zoom toward.
enum BrowserTabPromotionSourcePolicy {
    static func isPromotionSource(_ tab: BrowserTab, isSelected: Bool) -> Bool {
        isSelected && !tab.isStartPage
    }
}
