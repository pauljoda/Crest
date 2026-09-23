using CrestCore.Contracts;

namespace CrestCore.Generator;

/// Generates the contract codecs and models from the C# contract records.
///
/// `dotnet run --project CrestCore/tools/CrestCore.Generator [-- --check] [--root PATH]`
/// writes the C# codec, the two Swift files and the C tag header. With
/// `--check` it writes nothing and fails when any output is stale.
internal static class Program {
    #region Variables

    private const string CheckOption = "--check";
    private const string RootOption = "--root";

    #endregion

    #region Actions - Generation

    public static int Main(string[] args) {
        bool check = args.Contains(CheckOption);
        try {
            string root = RepositoryRoot(args);
            var schema = ContractSchema.Load(typeof(Intent).Assembly);
            var outputs = new Dictionary<string, string> {
                ["CrestCore/src/CrestCore.Native/Generated/ContractCodec.g.cs"] = CSharpCodecEmitter.Emit(schema),
                ["CrestShared/Infrastructure/Core/Generated/CoreContracts.generated.swift"] = SwiftEmitter.EmitContracts(schema),
                ["CrestShared/Infrastructure/Core/Generated/CoreCodec.generated.swift"] = SwiftEmitter.EmitCodec(schema),
                ["CrestContracts/include/crest_contracts.h"] = CHeaderEmitter.Emit(schema)
            };
            return check ? Check(root, outputs) : Write(root, outputs);
        } catch (ContractSchemaException error) {
            Console.Error.WriteLine($"error: {error.Message}");
            return 2;
        }
    }

    private static int Write(string root, Dictionary<string, string> outputs) {
        foreach (var (path, text) in outputs) {
            string file = Path.Combine(root, path);
            Directory.CreateDirectory(Path.GetDirectoryName(file)!);
            if (File.Exists(file) && File.ReadAllText(file) == text) continue;
            File.WriteAllText(file, text);
            Console.WriteLine($"Generated {path}");
        }
        Console.WriteLine("Contract sources are current.");
        return 0;
    }

    private static int Check(string root, Dictionary<string, string> outputs) {
        var stale = outputs.Where(output => {
            string file = Path.Combine(root, output.Key);
            return !File.Exists(file) || File.ReadAllText(file) != output.Value;
        }).Select(output => output.Key).ToList();
        foreach (var path in stale) Console.Error.WriteLine($"error: {path} is stale. Run Scripts/control-plane/generate-contracts.sh.");
        if (stale.Count == 0) Console.WriteLine("Contract sources are current.");
        return stale.Count == 0 ? 0 : 1;
    }

    /// The `--root` argument, or the nearest directory above the working
    /// directory that holds `CrestContracts/include`.
    private static string RepositoryRoot(string[] args) {
        int index = Array.IndexOf(args, RootOption);
        if (index >= 0 && index + 1 < args.Length) return Path.GetFullPath(args[index + 1]);
        for (var directory = new DirectoryInfo(Environment.CurrentDirectory); directory is not null; directory = directory.Parent)
            if (Directory.Exists(Path.Combine(directory.FullName, "CrestContracts", "include"))) return directory.FullName;
        throw new ContractSchemaException("Cannot find the repository root; pass --root.");
    }

    #endregion
}
