namespace CrestCore.Contracts;

public sealed class ProtocolException(string code) : Exception(code) {
    #region Variables

    public string Code { get; } = code;

    #endregion
}
