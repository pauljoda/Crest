namespace CrestCore.Contracts;

/// <summary>How long a Space keeps its history, archived tabs and downloads.</summary>
public sealed record DataRetentionPreferences(DataRetention History, DataRetention Archive, DataRetention Downloads);
