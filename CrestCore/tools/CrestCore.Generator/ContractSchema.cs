using System.Reflection;
using System.Security.Cryptography;
using System.Text;

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

/// A contract type the generator cannot describe.
internal sealed class ContractSchemaException(string message) : Exception(message);

/// Every contract type reachable from the roots, and the fingerprint of their
/// canonical description.
///
/// The roots are every concrete type assignable to `Intent`, `Change` or
/// `Rejection`, or deriving from `Query<>`. The closure adds the records and
/// enums their constructor parameters use.
internal sealed class ContractSchema {
    #region Variables

    public const int WireVersion = 1;

    private readonly Dictionary<Type, ContractRecord> records = [];
    private readonly Dictionary<Type, ContractEnum> enums = [];
    private readonly Dictionary<ContractRoot, List<ContractMember>> roots = [];
    private readonly NullabilityInfoContext nullability = new();

    /// Every record, root members included, in ordinal name order.
    public IReadOnlyList<ContractRecord> Records => [.. records.Values.OrderBy(record => record.Name, StringComparer.Ordinal)];

    public IReadOnlyList<ContractEnum> Enums => [.. enums.Values.OrderBy(item => item.Name, StringComparer.Ordinal)];

    public string Canonical { get; private set; } = "";

    public byte[] Fingerprint => SHA256.HashData(Encoding.UTF8.GetBytes(Canonical));

    #endregion

    #region Constructors

    private ContractSchema() { }

    #endregion

    #region Actions - Loading

    public static ContractSchema Load(Assembly assembly) {
        ArgumentNullException.ThrowIfNull(assembly);
        var schema = new ContractSchema();
        var candidates = assembly.GetExportedTypes().Where(type => type is { IsClass: true, IsAbstract: false }).ToList();
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
            throw new ContractSchemaException($"{type.Name}: contract types must be records.");
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

    #region Actions - Validation

    private void Validate() {
        var duplicate = records.Keys.Select(type => type.Name).Concat(enums.Keys.Select(type => type.Name))
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
        EnumField or RootField or ListField or OptionalField => 1,
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
    /// record's fields in order, and each root's tags.
    private string Describe() {
        var text = new StringBuilder();
        text.Append("crest-contracts wire ").Append(WireVersion).Append('\n');
        foreach (var item in Enums)
            text.Append(item.IsFlags ? "flags " : "enum ").Append(item.Name)
                .Append(string.Concat(item.Members.Select(member => $" {member.Key}={member.Value}"))).Append('\n');
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
        RecordField record => $"record:{record.Type.Name}",
        RootField root => $"union:{root.Root}",
        ListField list => $"list<{Describe(list.Element)}>",
        OptionalField optional => $"optional<{Describe(optional.Value)}>",
        _ => throw new ContractSchemaException($"Unknown field type {type}.")
    };

    #endregion
}
