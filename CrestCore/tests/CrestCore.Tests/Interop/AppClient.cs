using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Native;

using Xunit;

namespace CrestCore.Tests;

/// Drives the `crest_app_*` exports through bytes, as a native caller does.
internal sealed unsafe class AppClient : IDisposable {
    #region Variables

    public ulong Handle { get; }

    #endregion

    #region Constructors

    public AppClient() {
        ulong handle = 0;
        Assert.Equal(CoreStatus.Ok, Create(ContractCodec.Fingerprint, &handle));
        Handle = handle;
    }

    #endregion

    #region Actions - Lifecycle

    public static int Create(ReadOnlySpan<byte> fingerprint, ulong* handle) {
        fixed (byte* bytes = fingerprint) return ((delegate* unmanaged[Cdecl]<byte*, nuint, ulong*, int>)&Exports.AppCreate)(bytes, (nuint)fingerprint.Length, handle);
    }

    public int Destroy() => ((delegate* unmanaged[Cdecl]<ulong, int>)&Exports.AppDestroy)(Handle);

    public void Dispose() => Destroy();

    #endregion

    #region Actions - Messages

    /// The changes an intent published; fails the test on any other answer.
    public IReadOnlyList<Change> Send(Intent intent) {
        var (status, bytes) = Dispatch(Encode(writer => ContractCodec.WriteIntent(writer, intent)));
        Assert.Equal(CoreStatus.Ok, status);
        var reader = new WireReader(bytes);
        var changes = reader.ReadList(() => ContractCodec.ReadChange(reader));
        reader.EnsureEnd();
        return changes;
    }

    /// The rule that refused an intent; fails the test on any other answer.
    public Rejection Refuse(Intent intent) {
        var (status, bytes) = Dispatch(Encode(writer => ContractCodec.WriteIntent(writer, intent)));
        Assert.Equal(CoreStatus.Rejected, status);
        var reader = new WireReader(bytes);
        var rejection = ContractCodec.ReadRejection(reader);
        reader.EnsureEnd();
        return rejection;
    }

    public (int Status, byte[] Bytes) Dispatch(ReadOnlySpan<byte> intent) =>
        Call((delegate* unmanaged[Cdecl]<ulong, byte*, nuint, CrestBuffer*, int>)&Exports.AppDispatch, intent);

    public (int Status, byte[] Bytes) Ask(ReadOnlySpan<byte> query) =>
        Call((delegate* unmanaged[Cdecl]<ulong, byte*, nuint, CrestBuffer*, int>)&Exports.AppQuery, query);

    public static byte[] Encode(Action<WireWriter> write) {
        var writer = new WireWriter();
        write(writer);
        return writer.WrittenSpan.ToArray();
    }

    private (int Status, byte[] Bytes) Call(delegate* unmanaged[Cdecl]<ulong, byte*, nuint, CrestBuffer*, int> entry,
        ReadOnlySpan<byte> message) {
        CrestBuffer buffer;
        int status;
        fixed (byte* input = message) status = entry(Handle, input, (nuint)message.Length, &buffer);
        var bytes = buffer.Bytes == null ? [] : new ReadOnlySpan<byte>(buffer.Bytes, (int)buffer.Length).ToArray();
        ((delegate* unmanaged[Cdecl]<CrestBuffer*, void>)&Exports.BufferFree)(&buffer);
        Assert.True(buffer.Bytes == null && buffer.Length == 0);
        return (status, bytes);
    }

    #endregion
}
