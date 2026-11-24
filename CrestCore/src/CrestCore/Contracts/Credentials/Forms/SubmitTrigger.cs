namespace CrestCore.Contracts;

/// What sent a form, as the page script saw it: the page's own submit event,
/// Return in one of its fields, a submit control, or another button. Inside a
/// form element a submit control sends the form; anywhere else, and for any
/// other button, only a control labelled as sending it does, so a "Show
/// password" button never reads as a sign-in. A member travels as its index
/// in `All`, so `All` is append-only.
public sealed class SubmitTrigger {
    #region Static Variables

    public static readonly SubmitTrigger FormSubmit = new(name: "submit", sendsForm: true, sendsOtherScope: true);
    public static readonly SubmitTrigger ReturnKey = new(name: "return", sendsForm: true, sendsOtherScope: true);
    public static readonly SubmitTrigger SubmitControl = new(name: "submitControl", sendsForm: true, sendsOtherScope: false);
    public static readonly SubmitTrigger Button = new(name: "button", sendsForm: false, sendsOtherScope: false);

    public static IReadOnlyList<SubmitTrigger> All { get; } = [FormSubmit, ReturnKey, SubmitControl, Button];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether the trigger sends a form element whatever its label says.
    internal bool SendsForm { get; }

    /// Whether the trigger sends a scope that is not a form element, such as
    /// a single-page app's sign-in panel, whatever its label says.
    internal bool SendsOtherScope { get; }

    #endregion

    #region Constructors

    private SubmitTrigger(string name, bool sendsForm, bool sendsOtherScope) {
        Name = name;
        SendsForm = sendsForm;
        SendsOtherScope = sendsOtherScope;
    }

    #endregion
}
