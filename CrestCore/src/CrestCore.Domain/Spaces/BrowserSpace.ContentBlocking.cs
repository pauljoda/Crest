namespace CrestCore.Domain;

public sealed partial class BrowserSpace {
    public ContentBlockingPolicy ContentBlocking { get; private set; } = ContentBlockingPolicy.Balanced;
    public void SetContentBlocking(ContentBlockingPolicy policy) {
        EnsureAccessible();
        if (!Enum.IsDefined(policy)) throw new BrowserRuleException("invalid_content_blocking_policy");
        ContentBlocking = policy;
    }
}
