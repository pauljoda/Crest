using System.Reflection;
using System.Runtime.InteropServices;

namespace CrestDesktop.DevHost;

/// The native core's C ABI (CrestContracts/include), loaded from the library
/// the host was started with.
internal static unsafe partial class CoreLibrary {
    #region Types

    /// `crest_buffer_t`: bytes the core allocated, freed with `crest_buffer_free`.
    [StructLayout(LayoutKind.Sequential)]
    public struct Buffer {
        public byte* Bytes;
        public nuint Length;
    }

    /// `crest_engine_binding_t`, which the core copies at registration.
    [StructLayout(LayoutKind.Sequential)]
    public struct EngineBinding {
        public nint Context;
        public delegate* unmanaged[Cdecl]<nint, ulong, ulong, nint, nint, void> Attach;
        public delegate* unmanaged[Cdecl]<nint, byte*, nuint, void> Run;
    }

    #endregion

    #region Variables

    private const string Library = "CrestCore.Native";

    public const int Ok = 0, Rejected = 6;

    private static string? path;

    #endregion

    #region Actions - Loading

    /// Loads the core from `library`, a published CrestCore.Native.
    public static void Load(string library) {
        path = Path.GetFullPath(library);
        if (!File.Exists(path)) throw new FileNotFoundException("No native core at the given path.", path);
        NativeLibrary.SetDllImportResolver(typeof(CoreLibrary).Assembly, Resolve);
        uint version = crest_core_abi_version();
        if (version != 1) throw new InvalidOperationException($"The native core speaks ABI {version}, not 1.");
    }

    private static nint Resolve(string name, Assembly assembly, DllImportSearchPath? searchPath) =>
        name == Library && path is not null ? NativeLibrary.Load(path) : 0;

    #endregion

    #region Actions - Buffers

    /// The buffer's bytes, copied out, after which the core frees it.
    public static byte[] Take(ref Buffer buffer) {
        try {
            return buffer.Bytes == null ? [] : new ReadOnlySpan<byte>(buffer.Bytes, checked((int)buffer.Length)).ToArray();
        } finally {
            fixed (Buffer* owned = &buffer) crest_buffer_free(owned);
        }
    }

    #endregion

    #region Actions - Library

    [LibraryImport(Library)]
    public static partial uint crest_core_abi_version();

    [LibraryImport(Library)]
    public static partial int crest_app_create(byte* fingerprint, nuint length, byte* configuration, nuint configurationLength,
        out ulong app, Buffer* rejection);

    [LibraryImport(Library)]
    public static partial int crest_app_destroy(ulong app);

    [LibraryImport(Library)]
    public static partial int crest_app_dispatch(ulong app, byte* intent, nuint length, Buffer* output);

    [LibraryImport(Library)]
    public static partial int crest_app_query(ulong app, byte* query, nuint length, Buffer* output);

    [LibraryImport(Library)]
    public static partial int crest_app_drain(ulong app, Buffer* output);

    [LibraryImport(Library)]
    public static partial int crest_app_end_turn(ulong app);

    [LibraryImport(Library)]
    public static partial int crest_app_set_wake(ulong app, delegate* unmanaged[Cdecl]<nint, void> callback, nint context);

    [LibraryImport(Library)]
    public static partial void crest_buffer_free(Buffer* buffer);

    [LibraryImport(Library)]
    public static partial int crest_engine_register(ulong app, byte* fingerprint, nuint fingerprintLength, byte* registration,
        nuint registrationLength, EngineBinding* binding, out ulong engine, Buffer* rejection);

    [LibraryImport(Library)]
    public static partial int crest_engine_report(ulong app, ulong engine, byte* engineEvent, nuint length);

    [LibraryImport(Library)]
    public static partial int crest_engine_ask(ulong app, ulong engine, byte* question, nuint length,
        delegate* unmanaged[Cdecl]<nint, byte*, nuint, void> answer, nint context);

    #endregion
}
