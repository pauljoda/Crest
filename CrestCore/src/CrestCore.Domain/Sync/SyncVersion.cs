namespace CrestCore.Domain;

public readonly record struct SyncVersion(ulong Clock, Guid Device) : IComparable<SyncVersion> {
    public int CompareTo(SyncVersion other) {
        int clock = Clock.CompareTo(other.Clock);
        return clock != 0 ? clock : string.Compare(Device.ToString("D"), other.Device.ToString("D"), StringComparison.Ordinal);
    }
}
