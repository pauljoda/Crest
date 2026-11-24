using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace CrestCore.Contracts;

/// A key that makes one-time codes, as a site's setup key or QR code gives it:
/// `Secret`, the shared key in canonical base32 (uppercase, without spaces or
/// padding), the `Issuer` and `Account` it is for, empty where the setup names
/// neither, and how its codes are made: with `Algorithm`, `Digits` characters
/// long, a new one every `Period` seconds, written in `Style`.
[HoldsSecrets]
public sealed partial record OneTimeCodeSetup(string Secret, string Issuer, string Account, OneTimeCodeAlgorithm Algorithm, int Digits,
    int Period, OneTimeCodeStyle Style) {
    #region Static Variables

    /// The fewest bytes a key may hold: 80 bits, as RFC 4226 requires.
    internal const int ShortestSecretBytes = 10;

    /// The most bytes a key may hold.
    internal const int LongestSecretBytes = 128;

    /// The latest time a code is made for: the end of the year 9999, in
    /// seconds since 1970.
    private const double LatestTime = 253_402_300_800;

    /// The characters of RFC 4648's base32, each standing for its index.
    private const string Base32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    #endregion

    #region Variables

    /// Why the setup makes no codes, or null when it makes them.
    internal CodeSetupRefusal? Refusal => SecretRefusal(Secret) ?? Style.Refusal(Algorithm, Digits, Period);

    #endregion

    #region Actions - Codes

    /// The code for `now`, in seconds since 1970, and the times it is valid
    /// from and until.
    internal OneTimeCodeReading ReadingAt(double now) {
        if (Refusal is { } refusal) throw new Rejected(new InvalidCodeSetup(refusal));
        if (!double.IsFinite(now) || now < 0 || now > LatestTime) throw new Rejected(new InvalidCodeTime());
        long counter = (long)Math.Floor(now / Period);
        return new(CodeFor(counter), (double)counter * Period, (double)(counter + 1) * Period);
    }

    /// RFC 4226's code for the moving factor `counter`, which for a code of
    /// time is the number of periods since 1970: the HMAC of the counter's
    /// eight bytes, truncated to 31 bits at the offset its last byte's low
    /// four bits name, and written in the setup's style.
    internal string CodeFor(long counter) {
        byte[] key = Key();
        var moment = new byte[sizeof(long)];
        BinaryPrimitives.WriteInt64BigEndian(moment, counter);
        byte[] hash = Algorithm.Sign(key, moment);
        CryptographicOperations.ZeroMemory(key);
        int offset = hash[^1] & 0x0F;
        uint truncated = BinaryPrimitives.ReadUInt32BigEndian(hash.AsSpan(offset, sizeof(uint))) & 0x7FFF_FFFF;
        CryptographicOperations.ZeroMemory(hash);
        return Style.Write(truncated, Digits);
    }

    /// Why `secret` can't be a setup's key, or null when it can: it is base32
    /// of 10 to 128 bytes.
    private static CodeSetupRefusal? SecretRefusal(string secret) {
        if (secret.Any(character => !Base32.Contains(character, StringComparison.Ordinal)) || Bytes(secret) > LongestSecretBytes)
            return CodeSetupRefusal.InvalidSecret;
        return Bytes(secret) < ShortestSecretBytes ? CodeSetupRefusal.SecretTooShort : null;
    }

    /// How many whole bytes the base32 `secret` spells.
    private static int Bytes(string secret) => secret.Length * 5 / 8;

    /// The bytes the key's base32 spells, leaving out any bits after the last
    /// whole byte.
    private byte[] Key() {
        var key = new byte[Bytes(Secret)];
        int buffer = 0;
        int bits = 0;
        int written = 0;
        foreach (char character in Secret) {
            buffer = (buffer << 5) | Base32.IndexOf(character, StringComparison.Ordinal);
            bits += 5;
            if (bits < 8) continue;
            bits -= 8;
            key[written++] = (byte)(buffer >> bits);
            buffer &= (1 << bits) - 1;
        }
        return key;
    }

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("OneTimeCodeSetup { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(StringBuilder builder) {
        builder.Append($"Secret = <redacted>, Issuer = {Issuer}, Account = <redacted>, Algorithm = {Algorithm?.Name}, Digits = {Digits}, ")
            .Append($"Period = {Period}, Style = {Style?.Name}");
        return true;
    }

    #endregion
}
