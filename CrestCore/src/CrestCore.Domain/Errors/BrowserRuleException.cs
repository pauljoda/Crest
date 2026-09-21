namespace CrestCore.Domain;

public sealed class BrowserRuleException(string code) : Exception(code) {
    #region Variables

    public string Code { get; } = code;

    #endregion
}
