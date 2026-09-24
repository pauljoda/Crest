namespace CrestCore.Contracts;

/// <summary>How long an open tab nobody uses stays before cleanup archives it.</summary>
public enum CurrentTabCleanup { After12Hours, After24Hours, After7Days, After30Days, Never }
