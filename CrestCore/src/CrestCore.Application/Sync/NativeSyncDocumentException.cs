namespace CrestCore.Application;

public sealed class NativeSyncDocumentException(string code, string value) : Exception(code) {
    #region Variables

    public string Code { get; } = code;
    public string Value { get; } = value;

    #endregion
}
