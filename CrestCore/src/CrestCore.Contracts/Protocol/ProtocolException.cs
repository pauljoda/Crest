namespace CrestCore.Contracts;

public sealed class ProtocolException(string code) : Exception(code);
