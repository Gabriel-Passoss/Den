enum Schema {
    static let migrations = [initial, boards]

    private static let boards = """
        CREATE TABLE projects (
            id   TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            root TEXT NOT NULL UNIQUE
        ) STRICT;

        CREATE TABLE stages (
            id         TEXT PRIMARY KEY,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            position   INTEGER NOT NULL,
            name       TEXT NOT NULL,
            agent      TEXT,
            is_final   INTEGER NOT NULL,
            UNIQUE (project_id, position)
        ) STRICT;

        CREATE TABLE tasks (
            id                   TEXT PRIMARY KEY,
            project_id           TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            stage_id             TEXT NOT NULL REFERENCES stages(id),
            title                TEXT NOT NULL,
            details              TEXT NOT NULL,
            origin_app           TEXT,
            origin_key           TEXT,
            entered_stage_at     REAL NOT NULL,
            execution            TEXT NOT NULL,
            agent_moves_in_a_row INTEGER NOT NULL,
            session_id           TEXT REFERENCES sessions(id) ON DELETE SET NULL,
            history              TEXT NOT NULL,
            pendencies           TEXT NOT NULL,
            UNIQUE (project_id, origin_app, origin_key)
        ) STRICT;

        CREATE TABLE subtasks (
            id        TEXT PRIMARY KEY,
            task_id   TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            position  INTEGER NOT NULL,
            title     TEXT NOT NULL,
            progress  TEXT NOT NULL,
            execution TEXT NOT NULL,
            UNIQUE (task_id, position)
        ) STRICT;

        CREATE TRIGGER deleting_a_project_deletes_its_task_chats BEFORE DELETE ON projects
        BEGIN
            DELETE FROM sessions WHERE id IN (SELECT session_id FROM tasks WHERE project_id = OLD.id);
        END;
        """

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
