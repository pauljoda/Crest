/// Who started a navigation that may open a window or hand off to another app:
/// the person, by following a link or submitting a form, or the page itself.
enum BrowserPopupTrigger: Equatable {
    case explicitUserNavigation
    case scripted
}
