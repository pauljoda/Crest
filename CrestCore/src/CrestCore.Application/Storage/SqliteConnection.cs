using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// One connection to a session file and its `checkpoint(part, data)` table.
/// Not thread-safe: its owner serializes every call.
internal sealed class SqliteConnection : IDisposable {
    #region Variables

    /// A part is never empty and never larger than a session input may be.
    public const int MaximumPartBytes = NativeSessionAuthority.MaximumBytes;

    private const int BusyTimeoutMilliseconds = 2000;

    private nint handle;

    #endregion

    #region Constructors

    private SqliteConnection(nint handle) => this.handle = handle;

    /// Opens `source` with SQLite's `flags`; a URI source needs `Sqlite.OpenUri`.
    public static SqliteConnection Open(string source, int flags) {
        int result = Sqlite.sqlite3_open_v2(source, out var handle, flags | Sqlite.OpenFullMutex, null);
        if (result != Sqlite.Ok) {
            string message = handle != 0 ? Sqlite.Message(handle) : "";
            if (handle != 0) Sqlite.sqlite3_close_v2(handle);
            throw new StorageException(SqliteFailure.ReasonFor(result), $"Cannot open {source}: {message} ({result})");
        }
        var connection = new SqliteConnection(handle);
        Sqlite.sqlite3_busy_timeout(handle, BusyTimeoutMilliseconds);
        return connection;
    }

    #endregion

    #region Actions - Statements

    public void Execute(string sql) {
        int result = Sqlite.sqlite3_exec(handle, sql, 0, 0, 0);
        if (result != Sqlite.Ok) throw Failure(result);
    }

    /// Runs `body` inside `BEGIN IMMEDIATE … COMMIT`; any failure rolls back.
    public void InTransaction(Action body) {
        Execute("BEGIN IMMEDIATE");
        try {
            body();
            Execute("COMMIT");
        } catch {
            try { Execute("ROLLBACK"); } catch (StorageException) { }
            throw;
        }
    }

    /// The storage version the file records in `PRAGMA user_version`.
    public int ReadUserVersion() => Query("PRAGMA user_version", statement => {
        if (Sqlite.sqlite3_step(statement) != Sqlite.Row) throw Failure(Sqlite.sqlite3_extended_errcode(handle));
        return Sqlite.sqlite3_column_int(statement, 0);
    });

    private T Query<T>(string sql, Func<nint, T> body) {
        int prepared = Sqlite.sqlite3_prepare_v2(handle, sql, -1, out var statement, 0);
        if (prepared != Sqlite.Ok) throw Failure(prepared);
        try { return body(statement); } finally { Sqlite.sqlite3_finalize(statement); }
    }

    private StorageException Failure(int result) =>
        new(SqliteFailure.ReasonFor(result), $"{Sqlite.Message(handle)} ({result})");

    #endregion

    #region Actions - Parts

    /// A part's bytes, or null when the table does not hold it.
    public byte[]? Read(string part) => Query("SELECT data FROM checkpoint WHERE part=?", statement => {
        Bind(statement, part);
        int result = Sqlite.sqlite3_step(statement);
        if (result == Sqlite.Done) return null;
        if (result != Sqlite.Row) throw Failure(result);
        var data = Sqlite.ColumnBlob(statement, 0);
        return data.Length is > 0 and <= MaximumPartBytes
            ? data : throw new StorageException(StorageFailure.Damaged, $"The stored part {part} is empty or too large.");
    });

    /// Every part the table holds.
    public IReadOnlyList<string> Parts() => Query("SELECT part FROM checkpoint", statement => {
        var parts = new List<string>();
        while (true) {
            int result = Sqlite.sqlite3_step(statement);
            if (result == Sqlite.Done) return parts;
            if (result != Sqlite.Row) throw Failure(result);
            parts.Add(Sqlite.ColumnText(statement, 0));
        }
    });

    public void Write(string part, byte[] data) {
        if (data.Length is 0 or > MaximumPartBytes)
            throw new StorageException(StorageFailure.Unavailable, $"The part {part} is empty or too large to store.");
        Query("INSERT INTO checkpoint(part,data) VALUES(?,?) ON CONFLICT(part) DO UPDATE SET data=excluded.data", statement => {
            Bind(statement, part);
            int bound = Sqlite.BindBlob(statement, 2, data);
            if (bound != Sqlite.Ok) throw Failure(bound);
            int result = Sqlite.sqlite3_step(statement);
            return result == Sqlite.Done ? result : throw Failure(result);
        });
    }

    public void Remove(string part) => Query("DELETE FROM checkpoint WHERE part=?", statement => {
        Bind(statement, part);
        int result = Sqlite.sqlite3_step(statement);
        return result == Sqlite.Done ? result : throw Failure(result);
    });

    private void Bind(nint statement, string part) => Bind(statement, 1, part);

    #endregion

    #region Actions - Device store

    /// Creates the device store's tables beside the checkpoint table. They are
    /// additive: a build that predates them reads the file as before.
    /// `device_marker` holds the adoptions an older build knows, which it
    /// rewrites; `device_adoption` holds every adoption, and no older build
    /// touches it.
    public void CreateDeviceTables() {
        Execute("CREATE TABLE IF NOT EXISTS device_window (id TEXT PRIMARY KEY, shown_space TEXT NOT NULL, used INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_window_tab (window TEXT NOT NULL, space TEXT NOT NULL, tab TEXT, "
            + "PRIMARY KEY (window, space))");
        Execute("CREATE TABLE IF NOT EXISTS device_window_split (window TEXT NOT NULL, split_group TEXT NOT NULL, "
            + "position INTEGER NOT NULL, share REAL NOT NULL, PRIMARY KEY (window, split_group, position))");
        Execute("CREATE TABLE IF NOT EXISTS device_marker (name TEXT PRIMARY KEY)");
        Execute("CREATE TABLE IF NOT EXISTS device_adoption (name TEXT PRIMARY KEY)");
        Execute("CREATE TABLE IF NOT EXISTS device_site_permission (id TEXT PRIMARY KEY, space TEXT NOT NULL, scheme TEXT NOT NULL, "
            + "host TEXT NOT NULL, port INTEGER NOT NULL, permission TEXT NOT NULL, detail TEXT, decision TEXT NOT NULL, "
            + "modified_at REAL NOT NULL, position INTEGER NOT NULL)");
    }

    /// Everything the device store holds. A row whose identities or names do
    /// not read is left out.
    public DeviceRecords ReadDevice() => new(ReadWindows(), ReadSitePermissions(), ReadAdoptions());

    private List<SavedWindow> ReadWindows() {
        var windows = new Dictionary<Guid, (Guid ShownSpace, long Used)>();
        var tabs = new List<(Guid Window, ShownTab Tab)>();
        var shares = new List<(Guid Window, Guid Group, double Share)>();
        Rows("SELECT id, shown_space, used FROM device_window", statement => {
            if (Identity(statement, 0) is { } id && Identity(statement, 1) is { } shown)
                windows[id] = (shown, Sqlite.sqlite3_column_int64(statement, 2));
        });
        Rows("SELECT window, space, tab FROM device_window_tab", statement => {
            if (Identity(statement, 0) is { } window && Identity(statement, 1) is { } space)
                tabs.Add((window, new ShownTab(space, Sqlite.ColumnIsNull(statement, 2) ? null : Identity(statement, 2))));
        });
        Rows("SELECT window, split_group, share FROM device_window_split ORDER BY window, split_group, position", statement => {
            if (Identity(statement, 0) is { } window && Identity(statement, 1) is { } group)
                shares.Add((window, group, Sqlite.sqlite3_column_double(statement, 2)));
        });
        return [.. windows.Select(window => new SavedWindow(window.Key, window.Value.ShownSpace,
            [.. tabs.Where(tab => tab.Window == window.Key).Select(tab => tab.Tab)],
            [.. shares.Where(share => share.Window == window.Key).GroupBy(share => share.Group)
                .Select(group => new SplitColumnShares(group.Key, [.. group.Select(share => share.Share)]))],
            window.Value.Used)).OrderBy(record => record.Used)];
    }

    private List<SitePermissionRecord> ReadSitePermissions() {
        var records = new List<SitePermissionRecord>();
        Rows("SELECT id, space, scheme, host, port, permission, detail, decision, modified_at FROM device_site_permission "
            + "ORDER BY position", statement => {
                if (Identity(statement, 0) is not { } id || Identity(statement, 1) is not { } space
                    || SitePermission.Named(Sqlite.ColumnText(statement, 5)) is not { } permission
                    || SitePermissionDecision.Named(Sqlite.ColumnText(statement, 7)) is not { } decision) return;
                records.Add(new(id, space,
                    new SiteOrigin(Sqlite.ColumnText(statement, 2), Sqlite.ColumnText(statement, 3), Sqlite.sqlite3_column_int(statement, 4)),
                    permission, Sqlite.ColumnIsNull(statement, 6) ? null : Sqlite.ColumnText(statement, 6), decision,
                    Sqlite.sqlite3_column_double(statement, 8)));
            });
        return records;
    }

    private HashSet<DeviceAdoption> ReadAdoptions() {
        var adoptions = new HashSet<DeviceAdoption>();
        foreach (var table in new[] { "device_marker", "device_adoption" })
            Rows($"SELECT name FROM {table}", statement => {
                if (DeviceAdoption.Marked(Sqlite.ColumnText(statement, 0)) is { } adoption) adoptions.Add(adoption);
            });
        return adoptions;
    }

    /// Writes `records` over what the device store holds, rewriting only the
    /// parts that differ from `written`, which the store holds now; with null,
    /// every part. The caller runs it inside a transaction.
    public void WriteDevice(DeviceRecords records, DeviceRecords? written) {
        if (written is null || !records.Windows.SequenceEqual(written.Windows)) WriteWindows(records.Windows);
        if (written is null || !records.SitePermissions.SequenceEqual(written.SitePermissions)) WriteSitePermissions(records.SitePermissions);
        if (written is null || !records.Adopted.SetEquals(written.Adopted)) WriteAdoptions(records.Adopted);
    }

    private void WriteWindows(IReadOnlyList<SavedWindow> windows) {
        foreach (var table in new[] { "device_window", "device_window_tab", "device_window_split" }) Execute($"DELETE FROM {table}");
        foreach (var window in windows) {
            Insert("INSERT INTO device_window(id, shown_space, used) VALUES(?,?,?)", statement => {
                Bind(statement, 1, Spelling(window.Id));
                Bind(statement, 2, Spelling(window.ShownSpaceId));
                Checked(Sqlite.sqlite3_bind_int64(statement, 3, window.Used));
            });
            foreach (var tab in window.Tabs)
                Insert("INSERT INTO device_window_tab(window, space, tab) VALUES(?,?,?)", statement => {
                    Bind(statement, 1, Spelling(window.Id));
                    Bind(statement, 2, Spelling(tab.SpaceId));
                    Bind(statement, 3, tab.TabId is { } id ? Spelling(id) : null);
                });
            foreach (var group in window.Shares)
                for (int position = 0; position < group.Shares.Count; position++) {
                    int column = position;
                    Insert("INSERT INTO device_window_split(window, split_group, position, share) VALUES(?,?,?,?)", statement => {
                        Bind(statement, 1, Spelling(window.Id));
                        Bind(statement, 2, Spelling(group.GroupId));
                        Checked(Sqlite.sqlite3_bind_int64(statement, 3, column));
                        Checked(Sqlite.sqlite3_bind_double(statement, 4, group.Shares[column]));
                    });
                }
        }
    }

    /// The choices in storage order, with every value exactly as the record
    /// holds it: the capability and decision by `Name`, the time as the double
    /// it was.
    private void WriteSitePermissions(IReadOnlyList<SitePermissionRecord> records) {
        Execute("DELETE FROM device_site_permission");
        for (int position = 0; position < records.Count; position++) {
            var record = records[position];
            int index = position;
            Insert("INSERT INTO device_site_permission(id, space, scheme, host, port, permission, detail, decision, modified_at, position) "
                + "VALUES(?,?,?,?,?,?,?,?,?,?)", statement => {
                    Bind(statement, 1, Spelling(record.Id));
                    Bind(statement, 2, Spelling(record.Space));
                    Bind(statement, 3, record.Origin.Scheme);
                    Bind(statement, 4, record.Origin.Host);
                    Checked(Sqlite.sqlite3_bind_int64(statement, 5, record.Origin.Port));
                    Bind(statement, 6, record.Permission.Name);
                    Bind(statement, 7, record.Detail);
                    Bind(statement, 8, record.Decision.Name);
                    Checked(Sqlite.sqlite3_bind_double(statement, 9, record.ModifiedAt));
                    Checked(Sqlite.sqlite3_bind_int64(statement, 10, index));
                });
        }
    }

    /// Every adoption goes into `device_adoption`; the ones an older build
    /// knows also go into `device_marker`, which that build reads and rewrites.
    private void WriteAdoptions(IReadOnlySet<DeviceAdoption> adoptions) {
        foreach (var table in new[] { "device_marker", "device_adoption" }) Execute($"DELETE FROM {table}");
        foreach (var adoption in DeviceAdoption.All.Where(adoptions.Contains)) {
            Insert("INSERT INTO device_adoption(name) VALUES(?)", statement => Bind(statement, 1, adoption.Marker));
            if (adoption.OlderBuildsRead) Insert("INSERT INTO device_marker(name) VALUES(?)", statement => Bind(statement, 1, adoption.Marker));
        }
    }

    private void Rows(string sql, Action<nint> row) => Query(sql, statement => {
        while (true) {
            int result = Sqlite.sqlite3_step(statement);
            if (result == Sqlite.Done) return result;
            if (result != Sqlite.Row) throw Failure(result);
            row(statement);
        }
    });

    private void Insert(string sql, Action<nint> bind) => Query(sql, statement => {
        bind(statement);
        int result = Sqlite.sqlite3_step(statement);
        return result == Sqlite.Done ? result : throw Failure(result);
    });

    private void Bind(nint statement, int index, string? value) => Checked(Sqlite.BindText(statement, index, value));

    private void Checked(int result) {
        if (result != Sqlite.Ok) throw Failure(result);
    }

    private static Guid? Identity(nint statement, int column) =>
        Guid.TryParse(Sqlite.ColumnText(statement, column), out var id) ? id : null;

    /// An identity as the store spells it.
    private static string Spelling(Guid id) => id.ToString("D").ToUpperInvariant();

    #endregion

    #region Actions - Backup

    /// Copies every committed page, WAL included, into a new standalone file
    /// at `destination` that has no sidecars.
    public void Backup(string destination) {
        var target = Open(destination, Sqlite.OpenReadWrite | Sqlite.OpenCreate);
        try {
            nint backup = Sqlite.sqlite3_backup_init(target.handle, "main", handle, "main");
            if (backup == 0) throw target.Failure(Sqlite.sqlite3_extended_errcode(target.handle));
            int step = Sqlite.sqlite3_backup_step(backup, -1);
            int finished = Sqlite.sqlite3_backup_finish(backup);
            if (step != Sqlite.Done) throw target.Failure(step);
            if (finished != Sqlite.Ok) throw target.Failure(finished);
            target.Execute("PRAGMA journal_mode=DELETE");
        } finally {
            target.Dispose();
        }
    }

    #endregion

    #region Actions - Lifetime

    public void Dispose() {
        if (handle == 0) return;
        Sqlite.sqlite3_close_v2(handle);
        handle = 0;
    }

    #endregion
}
