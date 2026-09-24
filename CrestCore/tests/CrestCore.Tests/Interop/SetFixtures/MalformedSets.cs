using CrestCore.Contracts;

namespace CrestCore.Tests.Malformed;

/// `Hidden` is missing from `All`, so it has no wire tag.
public sealed class Unlisted {
    public static readonly Unlisted Shown = new("shown");
    public static readonly Unlisted Hidden = new("hidden");
    public static IReadOnlyList<Unlisted> All { get; } = [Shown];

    public string Name { get; }

    private Unlisted(string name) => Name = name;
}

/// A public constructor would let a value exist that no tag names.
public sealed class Constructible {
    public static readonly Constructible Only = new("only");
    public static IReadOnlyList<Constructible> All { get; } = [Only];

    public string Name { get; }

    public Constructible(string name) => Name = name;
}

/// A list is not a value Swift can spell as a literal.
public sealed class Listed {
    public static readonly Listed Only = new("only", ["part"]);
    public static IReadOnlyList<Listed> All { get; } = [Only];

    public string Name { get; }
    public IReadOnlyList<string> Parts { get; }

    private Listed(string name, IReadOnlyList<string> parts) {
        Name = name;
        Parts = parts;
    }
}

public sealed record SendUnlisted(Unlisted Value) : Intent;

public sealed record SendConstructible(Constructible Value) : Intent;

public sealed record SendListed(Listed Value) : Intent;
