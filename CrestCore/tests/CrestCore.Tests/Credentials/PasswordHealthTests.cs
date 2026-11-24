using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The health of a Space's saved passwords: which are reused, which are weak
/// and which are saved for a site without encryption, worked out from the
/// passwords the question carries and answered without any of them.
public sealed class PasswordHealthTests {
    private static readonly CrestApp Area = new();

    private static CheckedCredential Saved(string password, string username = "person", string site = "https://accounts.crest.test") {
        var address = new Uri(site);
        return new(Guid.NewGuid(), new CredentialOrigin(address.Scheme, address.IdnHost.Trim('[', ']'), address.Port), username, password);
    }

    private static IReadOnlyList<PasswordConcern> Concerns(CheckedCredential credential) =>
        Area.Query(new PasswordHealth([credential])).Credentials.Single().Concerns;

    [Fact]
    public void AReusedPasswordNamesTheOthersSharingIt() {
        var work = Saved("Correct-Horse-9-Battery");
        var home = Saved("Correct-Horse-9-Battery", site: "https://home.crest.test");
        var bank = Saved("Correct-Horse-9-Battery", site: "https://bank.crest.test");
        var unique = Saved("vT7#qLm2$xR9");

        var report = Area.Query(new PasswordHealth([work, home, unique, bank]));

        Assert.Equal([work.Id, home.Id, unique.Id, bank.Id], report.Credentials.Select(health => health.Id));
        Assert.Equal([[home.Id, bank.Id], [work.Id, bank.Id], [], [work.Id, home.Id]],
            report.Credentials.Select(health => health.SharedWith));
        Assert.Equal([[PasswordConcern.Reused], [PasswordConcern.Reused], [], [PasswordConcern.Reused]],
            report.Credentials.Select(health => health.Concerns));
        Assert.Equal(new DuplicateCredential(), Assert.Throws<Rejected>(() => Area.Query(new PasswordHealth([work, work]))).Rejection);
    }

    [Fact]
    public void AShortCommonPatternedOrPersonalPasswordIsWeak() {
        string[] weak = [
            "kT9#vB2", "abcdefghij", "ABCDEFGHIJK", "48271956302", "Password123!", "!!Sunshine2024", "Trustno1!", "aaaa1234",
            "qwertyuiop12", "abcabcabcabc", "zyxwvu9#Kp", "1q2w3e4r5t", "Ada!Lovelace99", "Grace#Crest-2024", "Kp#9mxAdaL"
        ];
        foreach (string password in weak) {
            var credential = Saved(password, username: password == "Kp#9mxAdaL" ? "ada@example.com" : "ada",
                site: password == "Grace#Crest-2024" ? "https://login.crest.co.uk" : "https://accounts.example.test");
            Assert.True(Concerns(credential).Contains(PasswordConcern.Weak), password);
        }

        // Long or mixed passwords, Crest's own grouped style included, are not.
        foreach (string password in new[] { "vT7#qLm2$xR9", "fexdub-Kurmo4-vizpaq", "correcthorsebatterystaple", "Bx7$Lq2!" })
            Assert.DoesNotContain(PasswordConcern.Weak, Concerns(Saved(password)));
    }

    [Fact]
    public void APasswordForPlainHttpOnAnotherDeviceIsInsecure() {
        Assert.Equal([PasswordConcern.InsecureSite], Concerns(Saved("vT7#qLm2$xR9", site: "http://accounts.crest.test")));
        foreach (string site in new[] { "https://accounts.crest.test", "http://localhost:8080", "http://127.0.0.1", "http://[::1]:3000",
            "http://dev.localhost" })
            Assert.Empty(Concerns(Saved("vT7#qLm2$xR9", site: site)));
    }
}
