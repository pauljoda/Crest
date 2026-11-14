using System.Runtime.InteropServices;
using System.Text;

using Microsoft.Win32.SafeHandles;

namespace CrestCore.Application;

/// Crest's content filter library, `crest_content_filter`: Brave's adblock
/// engine behind the C interface in
/// `CrestCore/native/ContentFilter/include/crest_content_filter.h`. Native AOT
/// links the prebuilt static library its lock names (`DirectPInvoke` in the
/// native project); a JIT host loads the dynamic library its build puts beside
/// the assembly.
internal static unsafe partial class ContentFilterLibrary {
    #region Types

    /// UTF-8 bytes lent to the library for one call.
    [StructLayout(LayoutKind.Sequential)]
    public struct Text {
        public byte* Bytes;
        public nuint Length;
    }

    /// A call made with UTF-8 text lent to the library.
    public delegate T LentText<T>(Text text);

    /// Bytes the library allocated, freed with `crest_content_filter_buffer_free`.
    [StructLayout(LayoutKind.Sequential)]
    public struct Allocation {
        public byte* Bytes;
        public nuint Length;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Request {
        public Text Url;
        public Text SourceUrl;
        public byte Kind;
        public byte Method;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Decision {
        public byte Verdict;
    }

    /// One retention of a compiled filter.
    public sealed class FilterHandle : SafeHandleZeroOrMinusOneIsInvalid {
        public FilterHandle() : base(ownsHandle: true) { }

        protected override bool ReleaseHandle() {
            crest_content_filter_release(handle);
            return true;
        }
    }

    /// A slot the library made.
    public sealed class SlotHandle : SafeHandleZeroOrMinusOneIsInvalid {
        public SlotHandle() : base(ownsHandle: true) { }

        protected override bool ReleaseHandle() {
            crest_content_filter_slot_destroy(handle);
            return true;
        }
    }

    #endregion

    #region Variables

    private const string Library = "crest_content_filter";

    public const int Ok = 0, InvalidArgument = 1, Unreadable = 2, Failed = 3;
    public const byte Allow = 0, Block = 1, Redirect = 2;

    /// The interface version this core is written against.
    private const uint AbiVersion = 3;

    #endregion

    #region Actions - Checking

    /// Refuses a library built for another interface, which a stale prebuilt
    /// archive or a hand-placed library would otherwise misread.
    public static void RequireCompatibleLibrary() {
        if (crest_content_filter_abi_version() != AbiVersion)
            throw new InvalidOperationException("The content filter library was built for another interface version.");
    }

    /// Throws for a status other than OK: every other status is a caller bug or
    /// a failure inside the library.
    public static void Require(int status, string operation) {
        if (status != Ok) throw new InvalidOperationException($"The content filter could not {operation} (status {status}).");
    }

    #endregion

    #region Actions - Texts

    /// Lends `text` as UTF-8 to the call `use` makes, and answers what it answers.
    public static T LendText<T>(string text, LentText<T> use) {
        var bytes = Encoding.UTF8.GetBytes(text);
        fixed (byte* lent = bytes) return use(new Text { Bytes = lent, Length = (nuint)bytes.Length });
    }

    #endregion

    #region Actions - Buffers

    /// The buffer's bytes, copied out, after which the buffer is freed.
    public static byte[] Take(ref Allocation buffer) {
        try {
            return buffer.Bytes == null ? [] : new ReadOnlySpan<byte>(buffer.Bytes, checked((int)buffer.Length)).ToArray();
        } finally {
            fixed (Allocation* owned = &buffer) crest_content_filter_buffer_free(owned);
        }
    }

    #endregion

    #region Actions - Library

    [LibraryImport(Library)]
    private static partial uint crest_content_filter_abi_version();

    [LibraryImport(Library)]
    public static partial int crest_content_filter_build(Text* lists, nuint count, out FilterHandle filter);

    [LibraryImport(Library)]
    public static partial int crest_content_filter_load(byte* bytes, nuint length, out FilterHandle filter);

    [LibraryImport(Library)]
    public static partial int crest_content_filter_build_with_resources(Text* lists, nuint count, nuint trusted,
        Text resources, out FilterHandle filter);

    [LibraryImport(Library)]
    public static partial int crest_content_filter_load_with_resources(byte* bytes, nuint length, Text resources,
        out FilterHandle filter);

    [LibraryImport(Library)]
    public static partial int crest_content_filter_save(FilterHandle filter, Allocation* buffer);

    [LibraryImport(Library)]
    private static partial void crest_content_filter_release(nint filter);

    [LibraryImport(Library)]
    public static partial int crest_content_filter_content_rules(Text* lists, nuint count, Allocation* buffer);

    [LibraryImport(Library)]
    public static partial int crest_content_filter_check(FilterHandle filter, Request* request, Decision* decision);

    [LibraryImport(Library)]
    public static partial int crest_content_filter_page_resources(FilterHandle filter, Text url, Allocation* buffer);

    [LibraryImport(Library)]
    public static partial int crest_content_filter_hidden_selectors(FilterHandle filter, Text query, Allocation* buffer);

    [LibraryImport(Library)]
    private static partial void crest_content_filter_buffer_free(Allocation* buffer);

    [LibraryImport(Library)]
    public static partial SlotHandle crest_content_filter_slot_create();

    [LibraryImport(Library)]
    public static partial int crest_content_filter_slot_install(SlotHandle slot, FilterHandle filter);

    /// `crest_content_filter_slot_install` with no filter, which empties the slot.
    [LibraryImport(Library, EntryPoint = "crest_content_filter_slot_install")]
    public static partial int crest_content_filter_slot_empty(SlotHandle slot, nint noFilter = 0);

    [LibraryImport(Library)]
    public static partial int crest_content_filter_slot_check(SlotHandle slot, Request* request, Decision* decision);

    [LibraryImport(Library)]
    private static partial void crest_content_filter_slot_destroy(nint slot);

    #endregion
}
