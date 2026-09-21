namespace CrestCore.Domain;

public sealed class BrowserRuleException(string code) : Exception(code) {
    public string Code { get; } = code;
}
