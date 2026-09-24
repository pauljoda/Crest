using CrestCore.Contracts;

namespace CrestCore.Application;

/// The session file the core owns: `session.sqlite` in the host's storage
/// directory, with the table, part names and pragmas every earlier release
/// used, so a rollback build still reads it.
///
/// One connection writes the file, one writer at a time. Accepted revisions
/// are saved behind by one worker thread, which always writes the newest one
/// and never an older revision over a newer one. Durable saves write on the
/// caller's thread before the revision is published. A journal is always
/// written in one transaction with the newest accepted session, so the
/// journal is never ahead of the session on disk. Parts whose bytes did not
/// change are not rewritten.
///
/// The writer lock is never taken while the session gate is held, and changes
/// are announced only after every storage lock is released.
internal sealed class SessionStorage : IDisposable {
    #region Variables

    public const string FileName = "session.sqlite";
    private const string RecoveryFileName = "session.recovery.sqlite";
    private const string RestoreMarkerSuffix = ".restore-pending";
    private const string TemporaryExtension = ".sqlite";
    private static readonly string[] SidecarSuffixes = ["-wal", "-shm"];
    private const int StorageVersion = 1;
    private const UnixFileMode OwnerOnly = UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute;

    private readonly SqliteConnection connection;
    private readonly Action<Change> announce;
    private readonly Thread worker;
    /// Guards the pending revision and the worker's wake-up; the worker waits on it.
    private readonly object queue = new();
    /// One writer at a time, and the only owner of the connection.
    private readonly Lock writing = new();
    /// The bytes of every part the file holds, as last committed.
    private readonly Dictionary<string, byte[]> written;
    private SessionState? writtenSession;
    private NativeSyncJournal? writtenJournal;
    private (SessionState Session, ulong Revision)? pending;
    private ulong writtenRevision;
    private bool pendingIsNew, stopping, closed;

    public string Directory { get; }

    #endregion

    #region Constructors

    private SessionStorage(string directory, SqliteConnection connection, Dictionary<string, byte[]> parts,
        NativeSyncJournal? journal, Action<Change> announce) {
        Directory = directory;
        this.connection = connection;
        written = parts;
        writtenJournal = journal;
        this.announce = announce;
        worker = new Thread(Run) { IsBackground = true, Name = "Crest session storage" };
        worker.Start();
    }

    /// Opens `session.sqlite` in `directory`, creating both when absent, and
    /// answers what it held in `loaded`. An existing file is validated
    /// read-only first, because a writable connection may replay or truncate a
    /// damaged WAL that recovery still needs. Throws `Rejected` naming why the
    /// file cannot be used.
    public static SessionStorage Open(string directory, Action<Change> announce, out StoredSession loaded) {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        ArgumentNullException.ThrowIfNull(announce);
        string path = Path.Combine(directory, FileName);
        if (File.Exists(path + RestoreMarkerSuffix)) throw new Rejected(new StorageRestoreInterrupted());
        try {
            CreateDirectory(directory);
            var validated = File.Exists(path) ? Validate(path) : null;
            var connection = SqliteConnection.Open(path, Sqlite.OpenReadWrite | Sqlite.OpenCreate);
            try {
                RequireVersion(connection.ReadUserVersion());
                connection.Execute("PRAGMA journal_mode=WAL");
                connection.Execute("PRAGMA synchronous=FULL");
                connection.InTransaction(() => {
                    connection.Execute("CREATE TABLE IF NOT EXISTS checkpoint (part TEXT PRIMARY KEY, data BLOB NOT NULL)");
                    connection.Execute($"PRAGMA user_version={StorageVersion}");
                });
                var parts = ReadAll(connection);
                loaded = validated is { } earlier && SameParts(earlier.Parts, parts) ? earlier.Session : StoredSession.Decode(parts);
                return new(directory, connection, parts, loaded.Journal, announce);
            } catch {
                connection.Dispose();
                throw;
            }
        } catch (StorageException error) {
            throw new Rejected(new StorageUnreadable(error.Reason));
        } catch (IOException) {
            throw new Rejected(new StorageUnreadable(StorageFailure.Unavailable));
        } catch (UnauthorizedAccessException) {
            throw new Rejected(new StorageUnreadable(StorageFailure.ReadOnly));
        }
    }

    #endregion

    #region Actions - Opening

    private static void CreateDirectory(string directory) {
        if (OperatingSystem.IsWindows()) System.IO.Directory.CreateDirectory(directory);
        else System.IO.Directory.CreateDirectory(directory, OwnerOnly);
    }

    /// Reads and decodes an existing file through a read-only connection. A
    /// cleanly closed WAL database has no sidecar, and a read-only connection
    /// cannot recreate one, so a file without a WAL is read as immutable.
    private static (Dictionary<string, byte[]> Parts, StoredSession Session)? Validate(string path) {
        bool standalone = !File.Exists(path + SidecarSuffixes[0]);
        string source = standalone ? new Uri(path).AbsoluteUri + "?immutable=1" : path;
        using var validation = SqliteConnection.Open(source, Sqlite.OpenReadOnly | Sqlite.OpenUri);
        int version = validation.ReadUserVersion();
        RequireVersion(version);
        if (version != StorageVersion) return null;
        var parts = ReadAll(validation);
        return (parts, StoredSession.Decode(parts));
    }

    private static void RequireVersion(int version) {
        if (version > StorageVersion) throw new Rejected(new StorageFromNewerApp());
        if (version < 0) throw new Rejected(new StorageUnreadable(StorageFailure.Damaged));
    }

    private static Dictionary<string, byte[]> ReadAll(SqliteConnection source) =>
        source.Parts().ToDictionary(part => part, part => source.Read(part)!, StringComparer.Ordinal);

    private static bool SameParts(Dictionary<string, byte[]> first, Dictionary<string, byte[]> second) =>
        first.Count == second.Count
        && first.All(part => second.TryGetValue(part.Key, out var bytes) && bytes.AsSpan().SequenceEqual(part.Value));

    #endregion

    #region Actions - Saving

    /// Hands the worker a published revision to save behind. A revision no
    /// newer than the one already pending or written is ignored.
    public void Enqueue(SessionState session, ulong revision) {
        ArgumentNullException.ThrowIfNull(session);
        lock (queue) {
            if (stopping || pending is { } current && current.Revision >= revision) return;
            pending = (session, revision);
            pendingIsNew = true;
            Monitor.Pulse(queue);
        }
    }

    /// Writes `session` at `revision`, with `journal` when it changed, before
    /// returning; `encoded` holds parts already encoded for it. Throws
    /// `StorageException` and leaves the file as it was when the write fails.
    public void Save(SessionState session, ulong revision, NativeSyncJournal? journal = null,
        NativeSessionCheckpoint? encoded = null) {
        ArgumentNullException.ThrowIfNull(session);
        Announce(Write(session, revision, journal, encoded));
    }

    /// Writes `journal` before returning, in one transaction with the newest
    /// accepted session that is not on disk yet.
    public void SaveJournal(NativeSyncJournal journal) {
        ArgumentNullException.ThrowIfNull(journal);
        Announce(Write(null, 0, journal));
    }

    /// Writes the first session into a file that holds none, with the journal
    /// that goes with it. Throws `StorageException` when the write fails.
    public void Install(SessionState session, NativeSyncJournal? journal) {
        ArgumentNullException.ThrowIfNull(session);
        lock (writing) {
            RequireOpen();
            if (written.ContainsKey(StoragePart.Core.Name)) throw new InvalidOperationException("The file already holds a session.");
            WriteParts(session, journal);
        }
    }

    private void Run() {
        while (true) {
            lock (queue) {
                while (!pendingIsNew && !stopping) Monitor.Wait(queue);
                if (!pendingIsNew) return;
                pendingIsNew = false;
            }
            Announce(WriteBehind());
        }
    }

    /// Saves the newest pending revision. A failure is published, and the
    /// revision stays pending for the next attempt.
    private Change? WriteBehind() {
        try {
            return Write(null, 0, null);
        } catch (Exception error) {
            return new StorageFailed(error is StorageException storage ? storage.Reason : StorageFailure.Unavailable);
        }
    }

    /// Writes one transaction under the writer lock: `session` or, without
    /// one, the newest pending revision, and `journal`. Answers `Saved` when
    /// the file now holds a newer revision.
    private Saved? Write(SessionState? session, ulong revision, NativeSyncJournal? journal,
        NativeSessionCheckpoint? encoded = null) {
        lock (writing) {
            RequireOpen();
            if (session is null) {
                lock (queue) {
                    if (pending is { } next && next.Revision > writtenRevision) (session, revision) = next;
                }
            } else if (revision <= writtenRevision) {
                throw new InvalidOperationException("A durable save must be newer than the file.");
            }
            if (session is null && journal is null) return null;
            WriteParts(session, journal, encoded);
            if (session is null) return null;
            writtenRevision = revision;
            lock (queue) {
                if (pending is { } saved && saved.Revision <= revision) pending = null;
            }
            return new Saved(checked((long)revision));
        }
    }

    /// Writes every part of `session` and `journal` whose bytes changed, in
    /// one transaction. The caller holds the writer lock.
    private void WriteParts(SessionState? session, NativeSyncJournal? journal, NativeSessionCheckpoint? encoded = null) {
        var puts = new List<(string Part, byte[] Data)>();
        var removals = new List<string>();
        if (session is not null) {
            var checkpoint = encoded ?? new NativeSessionCheckpoint(session);
            AddIfChanged(puts, StoragePart.Core, checkpoint.Core());
            var previous = writtenSession?.Spaces.ToDictionary(space => space.Id) ?? [];
            var retained = new HashSet<string>(StringComparer.Ordinal);
            foreach (var space in session.Spaces) {
                var part = StoragePart.History(space.Id);
                retained.Add(part.Name);
                // History that is the same list the file already holds needs no encoding.
                if (written.ContainsKey(part.Name) && previous.TryGetValue(space.Id, out var earlier)
                    && ReferenceEquals(earlier.History, space.History)) continue;
                AddIfChanged(puts, part, checkpoint.History(space.Id));
            }
            removals.AddRange(written.Keys.Where(name => new StoragePart(name).IsHistory && !retained.Contains(name)));
        }
        if (journal is not null && !ReferenceEquals(journal, writtenJournal)) AddIfChanged(puts, StoragePart.Journal, journal.Read());
        if (puts.Count > 0 || removals.Count > 0) {
            connection.InTransaction(() => {
                foreach (var (part, data) in puts) connection.Write(part, data);
                foreach (var part in removals) connection.Remove(part);
            });
            foreach (var (part, data) in puts) written[part] = data;
            foreach (var part in removals) written.Remove(part);
        }
        if (session is not null) writtenSession = session;
        if (journal is not null) writtenJournal = journal;
    }

    private void AddIfChanged(List<(string Part, byte[] Data)> puts, StoragePart part, byte[] data) {
        if (!written.TryGetValue(part.Name, out var current) || !current.AsSpan().SequenceEqual(data)) puts.Add((part.Name, data));
    }

    private void RequireOpen() {
        if (closed) throw new StorageException(StorageFailure.Unavailable, "The session file is closed.");
    }

    private void Announce(Change? change) {
        if (change is not null) announce(change);
    }

    #endregion

    #region Actions - Recovery

    /// Preserves the file as it is now, WAL included, as the standalone
    /// recovery checkpoint, when it holds both a session and a journal.
    /// Recovery restores it after a launch that cannot read the file.
    public void SaveRecoveryCheckpoint() {
        lock (writing) {
            RequireOpen();
            if (!written.ContainsKey(StoragePart.Core.Name) || !written.ContainsKey(StoragePart.Journal.Name)) return;
            string temporary = Path.Combine(Directory, Guid.NewGuid().ToString("D").ToUpperInvariant() + TemporaryExtension);
            try {
                connection.Backup(temporary);
                File.Move(temporary, Path.Combine(Directory, RecoveryFileName), overwrite: true);
            } finally {
                foreach (var file in SidecarSuffixes.Select(suffix => temporary + suffix).Prepend(temporary)) File.Delete(file);
            }
        }
    }

    #endregion

    #region Actions - Lifetime

    /// Saves any revision still pending, then closes the file.
    public void Dispose() {
        lock (queue) {
            if (stopping) return;
            stopping = true;
            Monitor.Pulse(queue);
        }
        worker.Join();
        Announce(WriteBehind() is Saved saved ? saved : null);
        lock (writing) {
            closed = true;
            connection.Dispose();
        }
    }

    #endregion
}
