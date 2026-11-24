enum Schema {
    static let migrations = [initial]

    private static let initial = """
        CREATE TABLE folders (
            id       TEXT PRIMARY KEY,
            name     TEXT NOT NULL,
            position INTEGER NOT NULL
        ) STRICT;

        CREATE TABLE sessions (
            id                TEXT PRIMARY KEY,
            title             TEXT NOT NULL,
            working_directory TEXT NOT NULL,
            folder_id         TEXT REFERENCES folders(id) ON DELETE SET NULL,
            position          INTEGER,
            created_at        REAL NOT NULL,
            touched_at        REAL NOT NULL
        ) STRICT;

        CREATE TABLE segments (
            id                    TEXT PRIMARY KEY,
            session_id            TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            ordinal               INTEGER NOT NULL,
            harness               TEXT NOT NULL,
            harness_session_id    TEXT NOT NULL,
            model                 TEXT NOT NULL,
            input_tokens          INTEGER NOT NULL,
            output_tokens         INTEGER NOT NULL,
            cache_read_tokens     INTEGER NOT NULL,
            cache_creation_tokens INTEGER NOT NULL,
            cost_usd              REAL NOT NULL,
            seeded_by             TEXT,
            context               TEXT,
            UNIQUE (session_id, ordinal)
        ) STRICT;

        CREATE TABLE entries (
            seq        INTEGER PRIMARY KEY AUTOINCREMENT,
            id         TEXT NOT NULL UNIQUE,
            segment_id TEXT NOT NULL REFERENCES segments(id) ON DELETE CASCADE,
            timestamp  REAL NOT NULL,
            payload    TEXT NOT NULL
        ) STRICT;

        CREATE INDEX entries_by_segment ON entries(segment_id, seq);

        CREATE TABLE session_preferences (
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            knob       TEXT NOT NULL,
            value      TEXT NOT NULL,
            PRIMARY KEY (session_id, knob)
        ) STRICT, WITHOUT ROWID;

        CREATE TABLE session_documents (
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            kind       TEXT NOT NULL,
            payload    TEXT NOT NULL,
            PRIMARY KEY (session_id, kind)
        ) STRICT, WITHOUT ROWID;

        CREATE TABLE harness_cache (
            harness    TEXT NOT NULL,
            kind       TEXT NOT NULL,
            directory  TEXT NOT NULL,
            payload    TEXT NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY (harness, kind, directory)
        ) STRICT, WITHOUT ROWID;
        """
}
