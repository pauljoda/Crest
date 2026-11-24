using System.Collections.Frozen;
using System.Globalization;
using System.Text;

namespace CrestCore.Contracts;

public sealed partial record CheckedCredential {
    #region Static Variables

    /// The fewest characters a password that is not weak holds.
    private const int MinimumLength = 8;
    /// The fewest characters a password of one kind of character holds
    /// before it is not weak for that alone.
    private const int MinimumSingleKindLength = 12;
    /// The fewest characters of the letters at a common password's heart.
    private const int MinimumCommonCore = 4;
    /// The fewest characters a username or a site's name holds for a password
    /// holding it to be weak.
    private const int MinimumNameLength = 3;
    /// The longest chunk whose repeats count as a run.
    private const int LongestRepeatedChunk = 4;

    /// The keyboard rows a run along keys follows, as typed without and with
    /// shift, on the common Latin layouts.
    private static readonly IReadOnlyList<string> KeyboardRows = ["`1234567890-=", "~!@#$%^&*()_+", "qwertyuiop[]\\", "asdfghjkl;'",
        "zxcvbnm,./", "qwertzuiop", "yxcvbnm", "azertyuiop", "qsdfghjklm", "wxcvbn"];

    /// Some of the passwords people choose most often, in lowercase.
    private static readonly FrozenSet<string> CommonPasswords = """
        123456 123456789 12345678 12345 1234567 1234567890 1234 111111 000000 123123 654321 666666 121212 112233 123321
        7777777 555555 11111111 987654321 159753 131313 696969 222222 1111 2000 2112 5150 8675309 147258369 789456123 102030
        159357 147258 123qwe 1q2w3e 1q2w3e4r 1q2w3e4r5t 1qaz2wsx 1qazxsw2 zaq12wsx zaq1zaq1 q1w2e3r4 qwe123 qwer1234 1234qwer
        qwerty qwerty1 qwerty12 qwerty123 qwertyu qwertyui qwertyuiop asdf asdfgh asdfghjkl zxcvbn zxcvbnm qazwsx azerty
        abc123 abcd1234 abc12345 a123456 123456a aa123456 a1b2c3 a1b2c3d4 1a2b3c abcdef abcdefg abcabc aaaaaa zxc123 asd123
        password password1 password12 password123 passw0rd p@ssw0rd p@ssword pass pass123 passpass letmein letmein1 welcome
        welcome1 welcome123 admin admin1 admin123 admin1234 administrator root toor login guest default changeme secret
        secret1 test test1 test123 testing user master master123 access hello hello123 iloveyou iloveyou1 iloveu loveme love
        lovely lover trustno1 whatever freedom forever friends family heaven blessed faith hope jesus angel angels angel1
        dragon dragon1 monkey monkey1 shadow shadow1 sunshine sunshine1 princess princess1 football football1 baseball
        baseball1 soccer hockey basketball golf tennis superman superman1 batman spiderman starwars startrek pokemon minecraft
        fortnite naruto matrix legend warrior knight wizard merlin gandalf ninja samurai pirate captain doctor soldier killer
        hunter hunter2 ranger harley mustang corvette camaro ferrari porsche mercedes thunder phoenix falcon eagle eagles
        tiger tigers panther dolphin dolphins rabbit chicken turtle spider viper cobra scorpion monster zombie hacker gamer
        player rockstar music guitar computer internet michael michael1 jennifer jordan jordan1 jordan23 thomas robert daniel
        andrew charlie charlie1 george william joshua matthew jessica ashley ashley1 amanda michelle nicole jasmine samantha
        taylor melissa heather hannah lauren sophie charlotte olivia emily jacob ethan tyler justin anthony kevin brandon jason
        nathan steven richard patrick martin david james john johnny peter oliver alexander alexis maggie ginger buster
        tigger pepper cookie peanut bailey buddy lucky lucky7 snoopy smokey sparky scooter boomer bigdog maverick coffee
        chocolate cheese banana orange purple yellow silver golden diamond summer winter spring autumn flower butterfly
        rainbow midnight cupcake sweetie honey kitty babygirl baby happy smile sunny star stars moon money cowboy cowboys
        yankees lakers steelers chelsea arsenal liverpool barcelona madrid juventus london paris canada america brazil mexico
        texas florida boston chicago dallas newyork army marine police iceman topgun bond007 ncc1701 thx1138 motdepasse
        passwort contrasena senha wachtwoord salasana lozinka
        """.Split((char[])[' ', '\n', '\r'], StringSplitOptions.RemoveEmptyEntries).ToFrozenSet(StringComparer.Ordinal);

    #endregion

    #region Variables

    /// Whether the password is easy to guess: it is shorter than 8
    /// characters, or under 12 and all of one kind (lowercase letters,
    /// uppercase letters, digits or the rest); it is one of the passwords
    /// people choose most often, ignoring case and the digits and symbols
    /// around it; runs make up most of it, of one character or a chunk of up
    /// to four repeated, or a sequence along the alphabet, the digits or a
    /// keyboard row; or it holds the username, the part of an email address
    /// before its `@`, or the site's name, ignoring case.
    internal bool HasWeakPassword {
        get {
            string lowered = Password.ToLowerInvariant();
            Rune[] runes = [.. lowered.EnumerateRunes()];
            return runes.Length < MinimumLength || runes.Length < MinimumSingleKindLength && IsOneKind(Password)
                || IsCommon(lowered) || IsMostlyRuns(runes) || HoldsName(lowered);
        }
    }

    #endregion

    #region Actions - Strength

    /// Whether every character of `password` is of one kind: lowercase
    /// letters, uppercase letters, digits or the rest.
    private static bool IsOneKind(string password) => password.EnumerateRunes()
        .Select(rune => Rune.IsLower(rune) ? UnicodeCategory.LowercaseLetter
            : Rune.IsUpper(rune) ? UnicodeCategory.UppercaseLetter
            : Rune.IsDigit(rune) ? UnicodeCategory.DecimalDigitNumber
            : UnicodeCategory.OtherSymbol)
        .Distinct().Count() <= 1;

    /// Whether `lowered`, a password in lowercase, is a common one: as it is,
    /// without the symbols around it, or without the digits and symbols
    /// around the letters at its heart.
    private static bool IsCommon(string lowered) {
        string word = Trimmed(lowered, char.IsLetterOrDigit);
        string core = Trimmed(lowered, char.IsLetter);
        return CommonPasswords.Contains(lowered) || CommonPasswords.Contains(word)
            || core.Length >= MinimumCommonCore && CommonPasswords.Contains(core);
    }

    /// `text` from its first to its last character that `keeps`.
    private static string Trimmed(string text, Func<char, bool> keeps) {
        int start = 0, end = text.Length;
        while (start < end && !keeps(text[start])) start++;
        while (end > start && !keeps(text[end - 1])) end--;
        return text[start..end];
    }

    /// Whether runs make up more than half of `runes`: three or more of one
    /// character, a chunk of two to four characters given twice or more, or
    /// three or more letters or digits in order either way, or keys in a row
    /// either way.
    private static bool IsMostlyRuns(Rune[] runes) {
        var covered = new bool[runes.Length];
        Cover(covered, reach: 1, minimum: 2, continues: index => runes[index] == runes[index - 1]);
        Cover(covered, reach: 1, minimum: 2, continues: index => Follows(runes[index - 1], runes[index], step: 1));
        Cover(covered, reach: 1, minimum: 2, continues: index => Follows(runes[index - 1], runes[index], step: -1));
        Cover(covered, reach: 1, minimum: 2, continues: index => IsNextKey(runes[index - 1], runes[index], step: 1));
        Cover(covered, reach: 1, minimum: 2, continues: index => IsNextKey(runes[index - 1], runes[index], step: -1));
        for (int chunk = 2; chunk <= LongestRepeatedChunk; chunk++)
            Cover(covered, reach: chunk, minimum: chunk, continues: index => runes[index] == runes[index - chunk]);
        return covered.Count(isCovered => isCovered) * 2 > runes.Length;
    }

    /// Marks in `covered` each stretch where at least `minimum` characters in
    /// a row `continue` the pattern from the character `reach` before them,
    /// together with the characters they continue it from.
    private static void Cover(bool[] covered, int reach, int minimum, Func<int, bool> continues) {
        int length = 0;
        for (int index = reach; index <= covered.Length; index++) {
            if (index < covered.Length && continues(index)) {
                length++;
                continue;
            }
            if (length >= minimum) Array.Fill(covered, true, index - length - reach, length + reach);
            length = 0;
        }
    }

    /// Whether `next` is the letter or digit `step` after `previous`.
    private static bool Follows(Rune previous, Rune next, int step) =>
        Rune.IsLetterOrDigit(previous) && Rune.IsLetterOrDigit(next) && next.Value - previous.Value == step;

    /// Whether `next` is the key `step` after `previous` along a keyboard row.
    private static bool IsNextKey(Rune previous, Rune next, int step) => KeyboardRows.Any(row => {
        int at = previous.IsBmp ? row.IndexOf((char)previous.Value, StringComparison.Ordinal) : -1;
        return at >= 0 && at + step >= 0 && at + step < row.Length && row[at + step] == next.Value;
    });

    /// Whether `lowered`, the password in lowercase, holds the username, the
    /// part of an email address before its `@`, or the site's name.
    private bool HoldsName(string lowered) {
        int at = Username.IndexOf('@', StringComparison.Ordinal);
        string?[] names = [Username, at > 0 ? Username[..at] : null, Origin.SiteName];
        return names.OfType<string>().Select(name => name.ToLowerInvariant())
            .Any(name => name.EnumerateRunes().Count() >= MinimumNameLength && lowered.Contains(name, StringComparison.Ordinal));
    }

    #endregion
}
