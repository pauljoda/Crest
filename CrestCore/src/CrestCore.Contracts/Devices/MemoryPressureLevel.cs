namespace CrestCore.Contracts;

/// How hard the system is asking for memory back. JSON policy requests spell
/// it `warning` or `critical`.
public enum MemoryPressureLevel { Warning, Critical }
