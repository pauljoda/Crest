using CrestCore.Application;

namespace CrestCore.Contracts;

/// What a page does when its engine cannot play the protected media its
/// document asked for and another engine plays it: move there at once, offer
/// to reload there first, or stay. The device store spells a choice as its
/// `Name`, so a name never changes. A choice travels as its index in `All`,
/// so `All` is append-only.
public sealed class ProtectedMediaFallback {
    #region Static Variables

    public static readonly ProtectedMediaFallback Automatic = new(name: "automatic", title: "Automatic", switches: true,
        asksFirst: false);

    public static readonly ProtectedMediaFallback Ask = new(name: "ask", title: "Ask", switches: true, asksFirst: true);

    public static readonly ProtectedMediaFallback Never = new(name: "never", title: "Never", switches: false, asksFirst: false);

    public static IReadOnlyList<ProtectedMediaFallback> All { get; } = [Automatic, Ask, Never];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the engine settings call the choice.
    [Localized]
    public string Title { get; }

    /// Whether a page ever leaves its engine for protected media.
    private readonly bool switches;
    /// Whether the page offers the move and waits for the person to accept it.
    private readonly bool asksFirst;

    /// Whether a page may leave its engine for protected media under this
    /// choice, so an offer it made before still moves it when accepted.
    internal bool Switches => switches;

    #endregion

    #region Constructors

    private ProtectedMediaFallback(string name, string title, bool switches, bool asksFirst) {
        Name = name;
        Title = title;
        this.switches = switches;
        this.asksFirst = asksFirst;
    }

    #endregion

    #region Actions - Pages

    /// Falls back to `fallback` for the document `page` shows, at `address`,
    /// once per document: a move at once, or an offer the person accepts or
    /// dismisses, or nothing.
    internal void FallBack(Pages pages, Page page, Engine fallback, string address, PageTurn turn) {
        if (!switches || !page.TryProtectedMediaFallback()) return;
        if (asksFirst) pages.Update(page, turn.Changes, () => page.OfferProtectedMedia(fallback));
        else pages.FallBack(page, fallback, address, turn);
    }

    /// Withdraws every offer the pages hold once this choice is made, when
    /// it never switches, so no bar outlives a choice to stay.
    internal void Withdraw(Pages pages, ChangeFeed changes) {
        if (!switches) pages.WithdrawProtectedMediaOffers(changes);
    }

    #endregion

    #region Actions - Lookup

    public static ProtectedMediaFallback? Named(string? name) => All.FirstOrDefault(fallback => fallback.Name == name);

    #endregion
}
