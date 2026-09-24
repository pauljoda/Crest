using CrestCore.Contracts;

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

    private void Bind(nint statement, string part) {
        int result = Sqlite.BindText(statement, 1, part);
        if (result != Sqlite.Ok) throw Failure(result);
    }

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
