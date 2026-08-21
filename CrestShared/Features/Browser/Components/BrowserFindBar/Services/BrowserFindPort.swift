/// Everything the find bar needs from the page layer, and nothing else.
///
/// The two shells reach different pages — one a pooled windowed page, the other
/// the compact shell's single resident page — but the bar only ever asks the
/// same three questions, and both pages already answer them with identical
/// signatures. They live here as closures rather than behind a protocol, for
/// the same reason `BrowserSidebarNavigationPort`'s do: there is no third
/// implementation to swap in, only two concrete pages, each bound where its
/// shell presents the bar.
///
/// `matchState` reads through its page at call time rather than carrying a
/// snapshot, so Observation still tracks it — the result the bar draws has to
/// change when WebKit answers.
///
/// None of the closures carries an isolation annotation, exactly like
/// `BrowserSidebarNavigationPort`: annotating them `@MainActor` would also make
/// them `@Sendable`, which the plain function values a View hands over are not.
/// The struct itself is isolated instead.
@MainActor
struct BrowserFindPort {
    /// Searches the page and moves to the match the direction asks for. An
    /// empty query clears the search rather than running it.
    let find: (String, BrowserFindDirection) -> Void

    /// What the page can say about the search right now.
    let matchState: () -> BrowserFindMatchState

    /// Closes the bar and clears the page's highlight.
    let dismiss: () -> Void
}
