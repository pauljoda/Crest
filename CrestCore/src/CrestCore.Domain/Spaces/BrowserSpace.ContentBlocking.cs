namespace CrestCore.Domain;

public sealed partial class BrowserSpace {
    #region Variables

    public ContentBlockingPolicy ContentBlocking { get; private set; } = ContentBlockingPolicy.Balanced;

    #endregion

    #region Mutators

    public void SetContentBlocking(ContentBlockingPolicy policy) {
        EnsureAccessible();
        if (!Enum.IsDefined(policy)) throw new BrowserRuleException(BrowserRuleCodes.InvalidContentBlockingPolicy);
        ContentBlocking = policy;
    }

    #endregion
}
