import Foundation

/// The database schema (PRAGMA user_version = number of migrations applied).
public enum Schema {
    public static let v1 = """
    CREATE TABLE meta (
        key   TEXT PRIMARY KEY,
        value TEXT
    );

    CREATE TABLE site (
        id             INTEGER PRIMARY KEY,
        name           TEXT NOT NULL UNIQUE COLLATE NOCASE,
        setting_type   TEXT NOT NULL,
        degree_program TEXT NOT NULL CHECK (degree_program IN ('Doctoral','Terminal Masters')),
        start_date     TEXT,
        end_date       TEXT,
        notes          TEXT,
        active         INTEGER NOT NULL DEFAULT 1
    );

    CREATE TABLE supervisor (
        id              INTEGER PRIMARY KEY,
        name            TEXT NOT NULL UNIQUE COLLATE NOCASE,
        supervisor_type TEXT NOT NULL,
        site_id         INTEGER REFERENCES site(id) ON DELETE SET NULL,
        active          INTEGER NOT NULL DEFAULT 1
    );

    CREATE TABLE client (
        id          INTEGER PRIMARY KEY,
        code        TEXT NOT NULL UNIQUE COLLATE NOCASE,
        site_id     INTEGER NOT NULL REFERENCES site(id),
        age_group   TEXT NOT NULL,
        race        TEXT,
        gender      TEXT,
        orientation TEXT,
        notes       TEXT,
        opened_on   TEXT,                       -- case opened (optional)
        closed_on   TEXT,                       -- case closed; NULL = open
        closure_note TEXT,
        created_at  TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE client_disability (
        client_id  INTEGER NOT NULL REFERENCES client(id) ON DELETE CASCADE,
        disability TEXT NOT NULL,
        PRIMARY KEY (client_id, disability)
    );

    CREATE TABLE client_group (
        id         INTEGER PRIMARY KEY,
        name       TEXT NOT NULL UNIQUE COLLATE NOCASE,
        group_type TEXT NOT NULL CHECK (group_type IN ('Group Therapy','Family Therapy','Couples Therapy')),
        site_id    INTEGER NOT NULL REFERENCES site(id),
        age_group  TEXT,
        notes      TEXT,
        closed_on  TEXT,                        -- group ended; NULL = ongoing
        closure_note TEXT
    );

    CREATE TABLE instrument (
        id     INTEGER PRIMARY KEY,
        name   TEXT NOT NULL UNIQUE COLLATE NOCASE,
        active INTEGER NOT NULL DEFAULT 1
    );

    CREATE TABLE slot (
        id         INTEGER PRIMARY KEY,
        weekday    INTEGER NOT NULL CHECK (weekday BETWEEN 0 AND 6),  -- Monday = 0
        time       TEXT,
        site_id    INTEGER NOT NULL REFERENCES site(id),
        category   TEXT NOT NULL DEFAULT 'intervention'
                   CHECK (category IN ('intervention','assessment','supervision','support')),
        activity   TEXT NOT NULL,
        minutes    INTEGER NOT NULL CHECK (minutes > 0),
        modality   TEXT NOT NULL DEFAULT 'In person',
        client_id     INTEGER REFERENCES client(id) ON DELETE CASCADE,
        group_id      INTEGER REFERENCES client_group(id) ON DELETE CASCADE,
        supervisor_id INTEGER REFERENCES supervisor(id) ON DELETE CASCADE,
        start_date TEXT NOT NULL,
        end_date   TEXT,
        active     INTEGER NOT NULL DEFAULT 1,
        CHECK (NOT (client_id IS NOT NULL AND group_id IS NOT NULL))
    );

    CREATE TABLE slot_skip (
        slot_id INTEGER NOT NULL REFERENCES slot(id) ON DELETE CASCADE,
        date    TEXT NOT NULL,
        PRIMARY KEY (slot_id, date)
    );

    CREATE TABLE entry (
        id            INTEGER PRIMARY KEY,
        date          TEXT NOT NULL,                 -- YYYY-MM-DD
        site_id       INTEGER NOT NULL REFERENCES site(id),
        category      TEXT NOT NULL CHECK (category IN ('intervention','assessment','supervision','support')),
        activity      TEXT NOT NULL,
        minutes       INTEGER NOT NULL CHECK (minutes > 0),
        modality      TEXT NOT NULL DEFAULT 'In person',
        client_id     INTEGER REFERENCES client(id),
        group_id      INTEGER REFERENCES client_group(id),
        supervisor_id INTEGER REFERENCES supervisor(id),
        purpose       TEXT,                          -- assessment: Clinical / Research
        specify       TEXT,                          -- for "(specify)" categories
        note          TEXT,
        slot_id       INTEGER REFERENCES slot(id) ON DELETE SET NULL,
        created_at    TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at    TEXT NOT NULL DEFAULT (datetime('now')),
        CHECK (NOT (client_id IS NOT NULL AND group_id IS NOT NULL)),
        CHECK (category = 'supervision' OR supervisor_id IS NULL)
    );
    CREATE INDEX entry_date   ON entry(date);
    CREATE INDEX entry_client ON entry(client_id);
    CREATE INDEX entry_group  ON entry(group_id);
    CREATE UNIQUE INDEX entry_slot_date ON entry(slot_id, date) WHERE slot_id IS NOT NULL;

    CREATE TABLE entry_instrument (
        entry_id      INTEGER NOT NULL REFERENCES entry(id) ON DELETE CASCADE,
        instrument_id INTEGER NOT NULL REFERENCES instrument(id),
        PRIMARY KEY (entry_id, instrument_id)
    );

    CREATE TABLE report (
        id          INTEGER PRIMARY KEY,
        client_id   INTEGER NOT NULL REFERENCES client(id),
        date        TEXT NOT NULL,
        report_type TEXT NOT NULL CHECK (report_type IN ('Standard Report','Integrated Report')),
        purpose     TEXT NOT NULL DEFAULT 'Clinical',
        note        TEXT
    );

    CREATE TABLE report_instrument (
        report_id     INTEGER NOT NULL REFERENCES report(id) ON DELETE CASCADE,
        instrument_id INTEGER NOT NULL REFERENCES instrument(id),
        PRIMARY KEY (report_id, instrument_id)
    );

    -- Entry with everything derived (degree, setting type, age, supervisor type).
    CREATE VIEW entry_full AS
    SELECT e.*,
           s.name           AS site_name,
           s.setting_type   AS setting_type,
           s.degree_program AS degree,
           c.code           AS client_code,
           g.name           AS group_name,
           g.group_type     AS group_type,
           COALESCE(c.age_group, g.age_group) AS age_group,
           sv.name          AS supervisor_name,
           sv.supervisor_type AS supervisor_type
    FROM entry e
    JOIN site s            ON s.id = e.site_id
    LEFT JOIN client c     ON c.id = e.client_id
    LEFT JOIN client_group g ON g.id = e.group_id
    LEFT JOIN supervisor sv  ON sv.id = e.supervisor_id;
    """

    /// v2: sessions added together share a batch_id (for the batch icon + batch editing).
    /// Backfill: sessions saved in the same second for the same client/group and activity
    /// (i.e. batch-added before this existed) become one batch. Recurring confirmations excluded.
    public static let v2 = """
    ALTER TABLE entry ADD COLUMN batch_id TEXT;
    CREATE INDEX entry_batch ON entry(batch_id) WHERE batch_id IS NOT NULL;
    UPDATE entry SET batch_id = 'legacy-' || created_at || '-' || COALESCE(client_id, '') || '-'
                               || COALESCE(group_id, '') || '-' || activity
    WHERE slot_id IS NULL
      AND (created_at, COALESCE(client_id, -1), COALESCE(group_id, -1), activity) IN (
          SELECT created_at, COALESCE(client_id, -1), COALESCE(group_id, -1), activity
          FROM entry WHERE slot_id IS NULL
          GROUP BY created_at, COALESCE(client_id, -1), COALESCE(group_id, -1), activity
          HAVING COUNT(*) > 1);
    DROP VIEW entry_full;
    CREATE VIEW entry_full AS
    SELECT e.*,
           s.name           AS site_name,
           s.setting_type   AS setting_type,
           s.degree_program AS degree,
           c.code           AS client_code,
           g.name           AS group_name,
           g.group_type     AS group_type,
           COALESCE(c.age_group, g.age_group) AS age_group,
           sv.name          AS supervisor_name,
           sv.supervisor_type AS supervisor_type
    FROM entry e
    JOIN site s            ON s.id = e.site_id
    LEFT JOIN client c     ON c.id = e.client_id
    LEFT JOIN client_group g ON g.id = e.group_id
    LEFT JOIN supervisor sv  ON sv.id = e.supervisor_id;
    """

    /// v3: sessions dated in the future are "planned" — they don't count anywhere until
    /// they're confirmed after their date. Backfill: anything entered ahead of its date.
    public static let v3 = """
    ALTER TABLE entry ADD COLUMN planned INTEGER NOT NULL DEFAULT 0;
    UPDATE entry SET planned = 1 WHERE date > date(created_at, 'localtime');
    """

    /// v4: the type you pick when adding a client (therapy / assessment). It's only a
    /// starting point — a client with any intervention sessions is always a therapy client,
    /// and one with only assessment sessions is an assessment client (see Client.kind).
    public static let v4 = """
    ALTER TABLE client ADD COLUMN kind TEXT NOT NULL DEFAULT 'therapy' CHECK (kind IN ('therapy','assessment'));
    UPDATE client SET kind = 'assessment'
    WHERE NOT EXISTS (SELECT 1 FROM entry e WHERE e.client_id = client.id AND e.category = 'intervention')
      AND EXISTS (SELECT 1 FROM entry e WHERE e.client_id = client.id AND e.category = 'assessment');
    """

    /// v5: semesters. Each runs from its start date to the day before the next one starts.
    /// New databases start with none; add your school's dates in Setup (or use a preset).
    public static let v5 = """
    CREATE TABLE semester (
        id            INTEGER PRIMARY KEY,
        name          TEXT NOT NULL,
        start_date    TEXT NOT NULL UNIQUE,
        supervisor_id INTEGER REFERENCES supervisor(id) ON DELETE SET NULL
    );
    """

    public static let migrations = [v1, v2, v3, v4, v5]

    public static func open(_ path: String) throws -> Database {
        let db = try Database(path: path)
        try db.exec("PRAGMA foreign_keys = ON")
        if path != ":memory:" { try db.exec("PRAGMA journal_mode = WAL") }
        try migrate(db)
        return db
    }

    /// Before a schema upgrade, keep an untouched copy of the database in `backupDir`
    /// (tracker-before-v<N>-<date>.db). Returns the copy's URL if one was made.
    @discardableResult
    public static func backupBeforeUpgrade(dbPath: String, backupDir: URL) throws -> URL? {
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        let db = try Database(path: dbPath)
        let version = (try db.scalar("PRAGMA user_version") as? Int) ?? 0
        guard version > 0, version < migrations.count else { return nil }
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let target = backupDir.appendingPathComponent("tracker-before-v\(migrations.count)-\(Day.today()).db")
        if !FileManager.default.fileExists(atPath: target.path) { try db.backup(to: target.path) }
        return target
    }

    public static func migrate(_ db: Database) throws {
        let version = (try db.scalar("PRAGMA user_version") as? Int) ?? 0
        guard version < migrations.count else { return }
        for i in version..<migrations.count {
            try db.transaction {
                try db.exec(migrations[i])
                try db.exec("PRAGMA user_version = \(i + 1)")
            }
        }
    }

    /// One snapshot per day (tracker-YYYY-MM-DD.db); keep the newest `keep`.
    @discardableResult
    public static func backup(_ db: Database, to dir: URL, keep: Int = 30,
                              today: String = Day.today()) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("tracker-\(today).db")
        try? fm.removeItem(at: target)
        try db.backup(to: target.path)
        let snaps = (try fm.contentsOfDirectory(atPath: dir.path))
            .filter { $0.hasPrefix("tracker-") && $0.hasSuffix(".db") }.sorted()
        for old in snaps.dropLast(keep) {
            try? fm.removeItem(at: dir.appendingPathComponent(old))
        }
        return target
    }
}
