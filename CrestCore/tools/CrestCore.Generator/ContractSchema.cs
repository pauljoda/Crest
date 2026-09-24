using System.Globalization;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

using CrestCore.Contracts;

namespace CrestCore.Generator;

/// The four kinds of contract type. Each root's concrete types form a union
/// whose wire tag is the type's index in ordinal name order.
internal enum ContractRoot { Intent, Change, Rejection, Query }

internal enum Primitive { Bool, Int, Long, Double, String, Guid, Date, Duration }

/// The wire shape of one constructor parameter.
internal abstract record FieldType;

internal sealed record PrimitiveField(Primitive Kind) : FieldType;

internal sealed record EnumField(Type Type) : FieldType;

internal sealed record RecordField(Type Type) : FieldType;

internal sealed record RootField(ContractRoot Root) : FieldType;

internal sealed record ListField(FieldType Element) : FieldType;

internal sealed record OptionalField(FieldType Value) : FieldType;

internal sealed record SetField(Type Type) : FieldType;

/// A fixed set's user-facing English text, which Swift receives as a
/// `LocalizedStringResource`. It never crosses the wire.
internal sealed record LocalizedField : FieldType;

/// A fixed set's nested `Kinds` enum, for the one switch a platform cannot
/// avoid. Swift receives it nested in the set's struct. It never crosses the wire.
internal sealed record KindsField(Type Type) : FieldType;

internal sealed record ContractField(string Name, FieldType Type);

/// A sealed positional record. Only its primary-constructor parameters cross the wire.
internal sealed record ContractRecord(Type Type, IReadOnlyList<ContractField> Fields) {
    public string Name => Type.Name;
}

/// One concrete type of a root, with its tag and, for a query, its answer.
internal sealed record ContractMember(ContractRecord Record, int Tag, FieldType? Answer) {
    public string Name => Record.Name;
}

internal sealed record ContractEnum(Type Type, bool IsFlags, IReadOnlyList<KeyValuePair<string, int>> Members) {
    public string Name => Type.Name;
}

/// A self-describing fixed set: a sealed class whose `public static readonly`
/// instances are its members. A member's wire tag is its index in the set's
/// `All`, so `All` is append-only. Each member carries the values of the set's
/// data properties into Swift; delegate members are the core's behavior and
/// stay there.
internal sealed record ContractSet(Type Type, IReadOnlyList<ContractField> Properties, IReadOnlyList<ContractSetMember> Members,
    IReadOnlyList<string> CoreOnly) {
    public string Name => Type.Name;
}

/// One member of a fixed set: the name of its static field, its wire tag, and
/// its value for each of the set's properties, in property order. A value is a
/// primitive, a `TimeSpan`, a `SetMemberReference` or null.
internal sealed record ContractSetMember(string Name, int Tag, IReadOnlyList<object?> Values);

/// A data value that is a member of another fixed set.
internal sealed record SetMemberReference(Type Set, string Member);

/// A localized data value: its English text and the note for translators.
internal sealed record LocalizedText(string Text, string? Comment);

/// A contract type the generator cannot describe.
internal sealed class ContractSchemaException(string message) : Exception(message);

/// Every contract type reachable from the roots, and the fingerprint of their
/// canonical description.
///
/// The roots are every concrete type assignable to `Intent`, `Change` or
/// `Rejection`, or deriving from `Query<>`. The closure adds the records,
/// enums and fixed sets their constructor parameters use.
internal sealed class ContractSchema {
    #region Variables

    public const int WireVersion = 1;

    /// The members a fixed set declares, and the one the generator adds.
    private const string SetAll = "All";
    private const string SetName = "Name";
    private const string SetTag = "Tag";
    private const string SetKinds = "Kinds";
    private const string CommentSuffix = "Comment";

    private readonly Dictionary<Type, ContractRecord> records = [];
    private readonly Dictionary<Type, ContractEnum> enums = [];
    private readonly Dictionary<Type, ContractSet> sets = [];
    private readonly Dictionary<ContractRoot, List<ContractMember>> roots = [];
    private readonly NullabilityInfoContext nullability = new();

    /// Every record, root members included, in ordinal name order.
    public IReadOnlyList<ContractRecord> Records => [.. records.Values.OrderBy(record => record.Name, StringComparer.Ordinal)];

    public IReadOnlyList<ContractEnum> Enums => [.. enums.Values.OrderBy(item => item.Name, StringComparer.Ordinal)];

    public IReadOnlyList<ContractSet> Sets => [.. sets.Values.OrderBy(set => set.Name, StringComparer.Ordinal)];

    public string Canonical { get; private set; } = "";

    public byte[] Fingerprint => SHA256.HashData(Encoding.UTF8.GetBytes(Canonical));

    #endregion

    #region Constructors

    private ContractSchema() { }

    #endregion

    #region Actions - Loading

    public static ContractSchema Load(Assembly assembly) {
        ArgumentNullException.ThrowIfNull(assembly);
        return Load(assembly.GetExportedTypes());
    }

    /// The schema whose roots are the given types' concrete contract types.
    public static ContractSchema Load(IEnumerable<Type> types) {
        ArgumentNullException.ThrowIfNull(types);
        var schema = new ContractSchema();
        var candidates = types.Where(type => type is { IsClass: true, IsAbstract: false }).ToList();
        schema.AddRoot(ContractRoot.Intent, candidates.Where(typeof(Intent).IsAssignableFrom));
        schema.AddRoot(ContractRoot.Change, candidates.Where(typeof(Change).IsAssignableFrom));
        schema.AddRoot(ContractRoot.Rejection, candidates.Where(typeof(Rejection).IsAssignableFrom));
        schema.AddRoot(ContractRoot.Query, candidates.Where(type => QueryAnswer(type) is not null));
        schema.Validate();
        schema.Canonical = schema.Describe();
        return schema;
    }

    private void AddRoot(ContractRoot root, IEnumerable<Type> types) {
        var ordered = types.OrderBy(type => type.Name, StringComparer.Ordinal).ToList();
        roots[root] = [.. ordered.Select((type, tag) => {
            var answer = root == ContractRoot.Query
                ? ResolveRequired(QueryAnswer(type)!, null, $"{type.Name} answer")
                : null;
            return new ContractMember(DescribeRecord(type), tag, answer);
        })];
    }

    private static Type? QueryAnswer(Type type) {
        for (var current = type.BaseType; current is not null; current = current.BaseType)
            if (current.IsGenericType && current.GetGenericTypeDefinition() == typeof(Query<>)) return current.GetGenericArguments()[0];
        return null;
    }

    #endregion

    #region Actions - Records

    private ContractRecord DescribeRecord(Type type) {
        if (records.TryGetValue(type, out var known)) return known;
        if (!type.IsClass || !type.IsSealed || type.IsGenericType || !type.IsPublic)
            throw new ContractSchemaException($"{type.Name}: contract types must be public, sealed, non-generic records.");
        if (type.GetProperty("EqualityContract", BindingFlags.NonPublic | BindingFlags.Instance) is null)
            throw new ContractSchemaException($"{type.Name}: contract types must be records, or fixed sets that declare a static All.");
        var constructors = type.GetConstructors(BindingFlags.Public | BindingFlags.Instance);
        if (constructors.Length != 1)
            throw new ContractSchemaException($"{type.Name}: a contract record needs exactly one public (primary) constructor.");
        // Register before resolving fields so a record may refer to itself through a list or an optional.
        var fields = new List<ContractField>();
        var record = new ContractRecord(type, fields);
        records[type] = record;
        foreach (var parameter in constructors[0].GetParameters()) {
            string where = $"{type.Name}.{parameter.Name}";
            var property = type.GetProperty(parameter.Name!, BindingFlags.Public | BindingFlags.Instance);
            if (property is null || property.PropertyType != parameter.ParameterType)
                throw new ContractSchemaException($"{where}: every constructor parameter must be a positional property.");
            fields.Add(new ContractField(parameter.Name!, Resolve(parameter.ParameterType, nullability.Create(parameter), where)));
        }
        return record;
    }

    private FieldType Resolve(Type type, NullabilityInfo? info, string where) {
        if (Nullable.GetUnderlyingType(type) is { } underlying) return new OptionalField(ResolveRequired(underlying, null, where));
        if (!type.IsValueType && info?.ReadState == NullabilityState.Nullable) return new OptionalField(ResolveRequired(type, info, where));
        return ResolveRequired(type, info, where);
    }

    private FieldType ResolveRequired(Type type, NullabilityInfo? info, string where) {
        if (type == typeof(bool)) return new PrimitiveField(Primitive.Bool);
        if (type == typeof(int)) return new PrimitiveField(Primitive.Int);
        if (type == typeof(long)) return new PrimitiveField(Primitive.Long);
        if (type == typeof(double)) return new PrimitiveField(Primitive.Double);
        if (type == typeof(string)) return new PrimitiveField(Primitive.String);
        if (type == typeof(Guid)) return new PrimitiveField(Primitive.Guid);
        if (type == typeof(DateTimeOffset)) return new PrimitiveField(Primitive.Date);
        if (type == typeof(TimeSpan)) return new PrimitiveField(Primitive.Duration);
        if (type == typeof(Intent)) return new RootField(ContractRoot.Intent);
        if (type == typeof(Change)) return new RootField(ContractRoot.Change);
        if (type == typeof(Rejection)) return new RootField(ContractRoot.Rejection);
        if (type.IsEnum) return DescribeEnum(type, where);
        if (type.IsGenericType && type.GetGenericTypeDefinition() == typeof(IReadOnlyList<>))
            return new ListField(Resolve(type.GetGenericArguments()[0], info?.GenericTypeArguments.FirstOrDefault(), $"{where}[]"));
        if (IsFixedSet(type)) return DescribeSet(type, where);
        if (type.IsClass && !type.IsAbstract && type.Assembly == typeof(Intent).Assembly) {
            DescribeRecord(type);
            return new RecordField(type);
        }
        throw new ContractSchemaException($"{where}: unsupported type {Display(type)}.");
    }

    private EnumField DescribeEnum(Type type, string where) {
        if (enums.ContainsKey(type)) return new EnumField(type);
        if (Enum.GetUnderlyingType(type) != typeof(int) || !type.IsPublic)
            throw new ContractSchemaException($"{where}: enum {type.Name} must be public and int-backed.");
        bool isFlags = type.IsDefined(typeof(FlagsAttribute), false);
        var members = Enum.GetNames(type).Select(name => new KeyValuePair<string, int>(name, (int)Enum.Parse(type, name)))
            .OrderBy(member => member.Value).ToList();
        bool valid = isFlags
            ? members.All(member => member.Value >= 0)
            : members.Select((member, index) => member.Value == index).All(matches => matches);
        if (!valid)
            throw new ContractSchemaException(isFlags
                ? $"{where}: flags enum {type.Name} must not have negative members."
                : $"{where}: enum {type.Name} must be contiguous from 0.");
        enums[type] = new ContractEnum(type, isFlags, members);
        return new EnumField(type);
    }

    private static string Display(Type type) => type.IsGenericType
        ? $"{type.Name[..type.Name.IndexOf('`', StringComparison.Ordinal)]}<{string.Join(", ", type.GetGenericArguments().Select(Display))}>"
        : type.Name;

    #endregion

    #region Actions - Fixed sets

    /// A sealed class that is not a record and declares a static `All`. The
    /// rest of the shape is checked when the set is described, so a class that
    /// nearly has it fails with the rule it broke.
    private static bool IsFixedSet(Type type) =>
        type is { IsClass: true, IsSealed: true, IsAbstract: false }
        && type.GetProperty("EqualityContract", BindingFlags.NonPublic | BindingFlags.Instance) is null
        && type.GetMember(SetAll, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static).Length > 0;

    private SetField DescribeSet(Type type, string where) {
        if (sets.ContainsKey(type)) return new SetField(type);
        string name = type.Name;
        if (!type.IsPublic || type.IsGenericType)
            throw new ContractSchemaException($"{where}: fixed set {name} must be public and non-generic.");
        if (type.GetConstructors(BindingFlags.Public | BindingFlags.Instance).Length > 0)
            throw new ContractSchemaException($"{name}: a fixed set's constructors must be private, so its static instances are its only members.");
        var instances = SetInstances(type);
        var properties = new List<ContractField>();
        var members = new List<ContractSetMember>();
        var coreOnly = new List<string>();
        // Register before resolving properties so a data member may name this set or one that names it.
        sets[type] = new ContractSet(type, properties, members, coreOnly);
        if (type.GetFields(BindingFlags.Public | BindingFlags.Instance).FirstOrDefault() is { } exposed)
            throw new ContractSchemaException($"{name}.{exposed.Name}: a fixed set exposes its data as get-only properties, not fields.");
        coreOnly.AddRange(type.GetFields(BindingFlags.NonPublic | BindingFlags.Instance)
            .Where(field => typeof(Delegate).IsAssignableFrom(field.FieldType)).Select(field => DeclaredName(field.Name)));
        var accessors = type.GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .Where(property => !typeof(Delegate).IsAssignableFrom(property.PropertyType)).OrderBy(property => property.MetadataToken).ToList();
        var comments = TranslatorComments(accessors, name);
        accessors.RemoveAll(comments.ContainsValue);
        foreach (var property in accessors) {
            string at = $"{name}.{property.Name}";
            if (property.Name == SetTag)
                throw new ContractSchemaException($"{at}: {SetTag} is the generated wire tag; give the property another name.");
            if (property.GetIndexParameters().Length > 0 || property.SetMethod is { IsPublic: true })
                throw new ContractSchemaException($"{at}: a fixed set's data members must be get-only properties.");
            var info = nullability.Create(property);
            properties.Add(new ContractField(property.Name, IsLocalized(property)
                ? ResolveLocalized(property.PropertyType, info, at)
                : ResolveSetData(property.PropertyType, info, at, type)));
        }
        int nameIndex = properties.FindIndex(property => property is { Name: SetName, Type: PrimitiveField { Kind: Primitive.String } });
        if (nameIndex < 0)
            throw new ContractSchemaException($"{name}: a fixed set needs a string {SetName}, which Swift's named(_:) looks up.");
        foreach (var (instance, tag) in instances.Select((instance, tag) => (instance, tag))) {
            string member = MemberName(type, instance, $"{name}.{SetAll}[{tag}]");
            members.Add(new ContractSetMember(member, tag, [.. accessors.Select((property, index) =>
                SetData(properties[index].Type, DataValue(property, instance, comments), $"{name}.{member}.{property.Name}"))]));
        }
        if (members.GroupBy(member => member.Values[nameIndex]).FirstOrDefault(group => group.Count() > 1) is { } shared)
            throw new ContractSchemaException($"{name}: {string.Join(" and ", shared.Select(member => member.Name))} share the {SetName} \"{shared.Key}\".");
        return new SetField(type);
    }

    /// The members of `All` in order, each one of the set's public static
    /// readonly instances, and every such instance listed exactly once.
    private static List<object> SetInstances(Type type) {
        string name = type.Name;
        var all = type.GetProperty(SetAll, BindingFlags.Public | BindingFlags.Static);
        if (all is null || all.PropertyType != typeof(IReadOnlyList<>).MakeGenericType(type) || all.SetMethod is { IsPublic: true }
            || all.GetValue(null) is not System.Collections.IEnumerable listed)
            throw new ContractSchemaException($"{name}.{SetAll}: a fixed set lists its members in a public static get-only IReadOnlyList<{name}>.");
        var fields = type.GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static).Where(field => field.FieldType == type).ToList();
        if (fields.FirstOrDefault(field => !field.IsPublic || !field.IsInitOnly || field.GetValue(null) is null) is { } hidden)
            throw new ContractSchemaException($"{name}.{hidden.Name}: a fixed set's instances must be public static readonly fields with a value.");
        var instances = listed.Cast<object?>().ToList();
        if (instances.Count == 0)
            throw new ContractSchemaException($"{name}.{SetAll}: a fixed set needs at least one member.");
        var seen = new HashSet<object>(ReferenceEqualityComparer.Instance);
        for (int tag = 0; tag < instances.Count; tag++) {
            if (instances[tag] is not { } instance || fields.Count(field => ReferenceEquals(field.GetValue(null), instance)) != 1)
                throw new ContractSchemaException($"{name}.{SetAll}[{tag}]: every member of {SetAll} must be exactly one of the set's static readonly fields.");
            if (!seen.Add(instance))
                throw new ContractSchemaException($"{name}.{SetAll}[{tag}]: {MemberName(type, instance, name)} appears in {SetAll} more than once.");
        }
        if (fields.FirstOrDefault(field => !seen.Contains(field.GetValue(null)!)) is { } missing)
            throw new ContractSchemaException($"{name}.{missing.Name}: every instance must appear in {SetAll}, because its wire tag is its index there.");
        return [.. instances.OfType<object>()];
    }

    /// A data member Swift can spell as a literal: a primitive, a duration,
    /// another fixed set or the set's own `Kinds`, any of them optional.
    private FieldType ResolveSetData(Type type, NullabilityInfo? info, string where, Type set) {
        if (Nullable.GetUnderlyingType(type) is { } underlying) return new OptionalField(ResolveSetData(underlying, null, where, set));
        if (!type.IsValueType && info?.ReadState == NullabilityState.Nullable) return new OptionalField(ResolveSetData(type, null, where, set));
        if (type == typeof(bool)) return new PrimitiveField(Primitive.Bool);
        if (type == typeof(int)) return new PrimitiveField(Primitive.Int);
        if (type == typeof(long)) return new PrimitiveField(Primitive.Long);
        if (type == typeof(double)) return new PrimitiveField(Primitive.Double);
        if (type == typeof(string)) return new PrimitiveField(Primitive.String);
        if (type == typeof(TimeSpan)) return new PrimitiveField(Primitive.Duration);
        if (type.IsEnum && type.DeclaringType == set && type.Name == SetKinds) return new KindsField(type);
        if (IsFixedSet(type)) return DescribeSet(type, where);
        throw new ContractSchemaException($"{where}: a fixed set's data members are bool, int, long, double, string, TimeSpan, another "
            + $"fixed set or the set's own nested {SetKinds}, optionally nullable, and {Display(type)} is none of them. Keep other state "
            + "private, or pass behavior as a delegate.");
    }

    private static bool IsLocalized(PropertyInfo property) => property.IsDefined(typeof(LocalizedAttribute), false);

    private static FieldType ResolveLocalized(Type type, NullabilityInfo info, string where) => type == typeof(string)
        ? info.ReadState == NullabilityState.Nullable ? new OptionalField(new LocalizedField()) : new LocalizedField()
        : throw new ContractSchemaException($"{where}: only a string member can be [Localized].");

    /// Each localized member's `<Member>Comment` sibling, which reaches Swift
    /// only inside the localized value.
    private static Dictionary<PropertyInfo, PropertyInfo> TranslatorComments(IReadOnlyList<PropertyInfo> accessors, string set) {
        var comments = new Dictionary<PropertyInfo, PropertyInfo>();
        foreach (var localized in accessors.Where(IsLocalized)) {
            if (accessors.FirstOrDefault(property => property.Name == $"{localized.Name}{CommentSuffix}") is not { } comment) continue;
            if (comment.PropertyType != typeof(string) || IsLocalized(comment))
                throw new ContractSchemaException($"{set}.{comment.Name}: a translator comment is a string that is not itself [Localized].");
            comments[localized] = comment;
        }
        return comments;
    }

    private static object? DataValue(PropertyInfo property, object instance, Dictionary<PropertyInfo, PropertyInfo> comments) {
        object? value = property.GetValue(instance);
        if (!IsLocalized(property) || value is not string text) return value;
        return new LocalizedText(text, comments.TryGetValue(property, out var comment) ? (string?)comment.GetValue(instance) : null);
    }

    private static object? SetData(FieldType type, object? value, string where) => (type, value) switch {
        (OptionalField, null) => null,
        (OptionalField optional, _) => SetData(optional.Value, value, where),
        (_, null) => throw new ContractSchemaException($"{where}: a data member that is not nullable holds null."),
        (SetField set, _) => new SetMemberReference(set.Type, MemberName(set.Type, value, where)),
        _ => value
    };

    private static string MemberName(Type set, object instance, string where) =>
        set.GetFields(BindingFlags.Public | BindingFlags.Static)
            .FirstOrDefault(field => field.FieldType == set && ReferenceEquals(field.GetValue(null), instance))?.Name
        ?? throw new ContractSchemaException($"{where}: the value is not one of {set.Name}'s static instances.");

    /// `<Applies>k__BackingField` is the field behind the property `Applies`.
    private static string DeclaredName(string field) =>
        field.StartsWith('<') && field.IndexOf('>', StringComparison.Ordinal) is > 1 and var end ? field[1..end] : field;

    #endregion

    #region Actions - Validation

    private void Validate() {
        var duplicate = records.Keys.Select(type => type.Name).Concat(enums.Keys.Select(type => type.Name))
            .Concat(sets.Keys.Select(type => type.Name))
            .GroupBy(name => name, StringComparer.Ordinal).FirstOrDefault(group => group.Count() > 1);
        if (duplicate is not null)
            throw new ContractSchemaException($"{duplicate.Key}: contract type names must be unique, because Swift has one namespace.");
        foreach (var record in records.Values)
            foreach (var field in record.Fields) ValidateLists(field.Type, $"{record.Name}.{field.Name}");
    }

    /// A list's count is checked against the bytes that remain, so every
    /// element must occupy at least one byte.
    private void ValidateLists(FieldType type, string where) {
        switch (type) {
            case ListField list:
                if (MinimumSize(list.Element, []) == 0)
                    throw new ContractSchemaException($"{where}: list elements must have a nonzero wire size.");
                ValidateLists(list.Element, where);
                break;
            case OptionalField optional:
                ValidateLists(optional.Value, where);
                break;
        }
    }

    private int MinimumSize(FieldType type, HashSet<Type> visiting) => type switch {
        PrimitiveField { Kind: Primitive.Bool } => 1,
        PrimitiveField { Kind: Primitive.Int } => 4,
        PrimitiveField { Kind: Primitive.Guid } => 16,
        PrimitiveField { Kind: Primitive.String } => 1,
        PrimitiveField => 8,
        EnumField or SetField or RootField or ListField or OptionalField => 1,
        RecordField record => RecordMinimumSize(record.Type, visiting),
        _ => throw new ContractSchemaException($"Unknown field type {type}.")
    };

    private int RecordMinimumSize(Type type, HashSet<Type> visiting) {
        if (!visiting.Add(type))
            throw new ContractSchemaException($"{type.Name}: a record cannot contain itself except through a list or an optional.");
        int size = records[type].Fields.Sum(field => MinimumSize(field.Type, visiting));
        visiting.Remove(type);
        return size;
    }

    #endregion

    #region Mutators

    /// The root's concrete types in tag order.
    public IReadOnlyList<ContractMember> Members(ContractRoot root) => roots[root];

    #endregion

    #region Actions - Canonical form

    /// The text the fingerprint hashes: the wire version, every enum, every
    /// fixed set's members in `All` order with their data, every record's
    /// fields in order, and each root's tags.
    private string Describe() {
        var text = new StringBuilder();
        text.Append("crest-contracts wire ").Append(WireVersion).Append('\n');
        foreach (var item in Enums)
            text.Append(item.IsFlags ? "flags " : "enum ").Append(item.Name)
                .Append(string.Concat(item.Members.Select(member => $" {member.Key}={member.Value}"))).Append('\n');
        foreach (var set in Sets)
            text.Append("set ").Append(set.Name).Append('(')
                .Append(string.Join(", ", set.Properties.Select(property => $"{property.Name}: {Describe(property.Type)}"))).Append(')')
                .Append(string.Concat(set.Members.Select(member =>
                    $" {member.Name}={member.Tag}({string.Join(", ", member.Values.Select(DescribeValue))})"))).Append('\n');
        foreach (var record in Records)
            text.Append("record ").Append(record.Name).Append('(')
                .Append(string.Join(", ", record.Fields.Select(field => $"{field.Name}: {Describe(field.Type)}"))).Append(")\n");
        foreach (var root in Enum.GetValues<ContractRoot>())
            foreach (var member in Members(root))
                text.Append(root.ToString().ToLowerInvariant()).Append(' ').Append(member.Tag).Append(' ').Append(member.Name)
                    .Append(member.Answer is { } answer ? $" -> {Describe(answer)}" : "").Append('\n');
        return text.ToString();
    }

    public static string Describe(FieldType type) => type switch {
        PrimitiveField primitive => primitive.Kind.ToString().ToLowerInvariant(),
        EnumField item => $"enum:{item.Type.Name}",
        SetField set => $"set:{set.Type.Name}",
        LocalizedField => "localized",
        KindsField kinds => $"kinds<{string.Join(", ", Enum.GetNames(kinds.Type))}>",
        RecordField record => $"record:{record.Type.Name}",
        RootField root => $"union:{root.Root}",
        ListField list => $"list<{Describe(list.Element)}>",
        OptionalField optional => $"optional<{Describe(optional.Value)}>",
        _ => throw new ContractSchemaException($"Unknown field type {type}.")
    };

    private static string DescribeValue(object? value) => value switch {
        null => "null",
        bool flag => flag ? "true" : "false",
        string text => $"\"{JsonEncodedText.Encode(text)}\"",
        double number => number.ToString("R", CultureInfo.InvariantCulture),
        TimeSpan duration => $"{duration.Ticks.ToString(CultureInfo.InvariantCulture)}ticks",
        Enum kind => kind.ToString(),
        int or long => Convert.ToString(value, CultureInfo.InvariantCulture)!,
        SetMemberReference reference => $"{reference.Set.Name}.{reference.Member}",
        LocalizedText text => $"localized({DescribeValue(text.Text)}, {DescribeValue(text.Comment)})",
        _ => throw new ContractSchemaException($"Unknown set value {value}.")
    };

    #endregion
}
