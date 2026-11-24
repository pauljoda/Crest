using System.Security.Cryptography;

namespace CrestCore.Contracts;

/// The HMAC hash a one-time code is made with, as RFC 6238 names it. `Name`
/// is the spelling of an otpauth link's `algorithm` parameter. A member
/// travels as its index in `All`, so `All` is append-only.
public sealed class OneTimeCodeAlgorithm {
    #region Static Variables

    public static readonly OneTimeCodeAlgorithm Sha1 = new(name: "SHA1", sign: HMACSHA1.HashData);
    public static readonly OneTimeCodeAlgorithm Sha256 = new(name: "SHA256", sign: HMACSHA256.HashData);
    public static readonly OneTimeCodeAlgorithm Sha512 = new(name: "SHA512", sign: HMACSHA512.HashData);

    public static IReadOnlyList<OneTimeCodeAlgorithm> All { get; } = [Sha1, Sha256, Sha512];

    #endregion

    #region Variables

    public string Name { get; }

    /// The HMAC of a message under a key.
    private readonly Func<byte[], byte[], byte[]> sign;

    #endregion

    #region Constructors

    private OneTimeCodeAlgorithm(string name, Func<byte[], byte[], byte[]> sign) {
        Name = name;
        this.sign = sign;
    }

    #endregion

    #region Actions - Lookup

    public static OneTimeCodeAlgorithm? Named(string? name) => All.FirstOrDefault(algorithm => algorithm.Name == name);

    /// The algorithm a link spells `spelling`, in any case and with or without
    /// the hyphen of `SHA-1`, or null when it names none Crest knows.
    internal static OneTimeCodeAlgorithm? Spelled(string spelling) {
        ArgumentNullException.ThrowIfNull(spelling);
        string compact = spelling.Replace("-", "", StringComparison.Ordinal).Trim();
        return All.FirstOrDefault(algorithm => string.Equals(algorithm.Name, compact, StringComparison.OrdinalIgnoreCase));
    }

    #endregion

    #region Actions - Signing

    /// The HMAC of `message` under `key`.
    internal byte[] Sign(byte[] key, byte[] message) => sign(key, message);

    #endregion
}
