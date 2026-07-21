import CSQLite
import Foundation

enum DatabaseError: LocalizedError {
    case open(String)
    case execute(String)

    var errorDescription: String? {
        switch self {
        case .open(let message): "Could not open the database: \(message)"
        case .execute(let message): "Database error: \(message)"
        }
    }
}

final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSLock()

    init(path: String) throws {
        if sqlite3_open(path, &handle) != SQLITE_OK {
            throw DatabaseError.open(String(cString: sqlite3_errmsg(handle)))
        }
        try execute("""
            CREATE TABLE IF NOT EXISTS time_entries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              project_id INTEGER,
              task TEXT NOT NULL,
              started_at REAL NOT NULL,
              ended_at REAL
            );
            CREATE TABLE IF NOT EXISTS projects (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL COLLATE NOCASE UNIQUE,
              hourly_rate REAL NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS app_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_entries_started_at ON time_entries(started_at DESC);
            CREATE INDEX IF NOT EXISTS idx_entries_project_started_at ON time_entries(project_id, started_at DESC);
            CREATE INDEX IF NOT EXISTS idx_entries_ended_at ON time_entries(ended_at);
            """)
        try migrateProjects()
    }

    deinit { sqlite3_close(handle) }

    func insert(projectID: Int64, task: String, startedAt: Date) throws -> Int64 {
        try locked {
            let sql = "INSERT INTO time_entries(project_id, task, started_at) VALUES (?, ?, ?)"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, projectID)
            sqlite3_bind_text(statement, 2, task, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(statement, 3, startedAt.timeIntervalSince1970)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
            return sqlite3_last_insert_rowid(handle)
        }
    }

    func insertProject(name: String, hourlyRate: Double = 0) throws -> Project {
        try locked {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "INSERT INTO projects(name, hourly_rate) VALUES (?, ?)", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(statement, 2, max(0, hourlyRate))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
            return Project(id: sqlite3_last_insert_rowid(handle), name: name, hourlyRate: max(0, hourlyRate))
        }
    }

    func fetchProjects() throws -> [Project] {
        try locked {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "SELECT id, name, hourly_rate FROM projects ORDER BY name COLLATE NOCASE", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            var items: [Project] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                items.append(Project(id: sqlite3_column_int64(statement, 0), name: String(cString: sqlite3_column_text(statement, 1)), hourlyRate: sqlite3_column_double(statement, 2)))
            }
            return items
        }
    }

    func updateProject(id: Int64, name: String, hourlyRate: Double) throws {
        try locked {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "UPDATE projects SET name = ?, hourly_rate = ? WHERE id = ?", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(statement, 2, max(0, hourlyRate))
            sqlite3_bind_int64(statement, 3, id)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        }
    }

    func deleteProject(id: Int64, fallbackProjectID: Int64) throws {
        try locked {
            var updateStatement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "UPDATE time_entries SET project_id = ? WHERE project_id = ?", -1, &updateStatement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(updateStatement) }
            sqlite3_bind_int64(updateStatement, 1, fallbackProjectID)
            sqlite3_bind_int64(updateStatement, 2, id)
            guard sqlite3_step(updateStatement) == SQLITE_DONE else { throw lastError() }

            var deleteStatement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "DELETE FROM projects WHERE id = ?", -1, &deleteStatement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(deleteStatement) }
            sqlite3_bind_int64(deleteStatement, 1, id)
            guard sqlite3_step(deleteStatement) == SQLITE_DONE else { throw lastError() }
        }
    }

    func fetchExportColumns() throws -> [ExportColumn] {
        try locked {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "SELECT value FROM app_settings WHERE key = 'export_columns'", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let valuePointer = sqlite3_column_text(statement, 0)
            else { return ExportColumn.allCases }
            let value = String(cString: valuePointer)
            let columns = value.split(separator: ",").compactMap { ExportColumn(rawValue: String($0)) }
            return columns.isEmpty ? ExportColumn.allCases : ExportColumn.allCases.filter { columns.contains($0) }
        }
    }

    func saveExportColumns(_ columns: [ExportColumn]) throws {
        try locked {
            let safeColumns = columns.isEmpty ? ExportColumn.allCases : ExportColumn.allCases.filter { columns.contains($0) }
            let value = safeColumns.map(\.rawValue).joined(separator: ",")
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "INSERT OR REPLACE INTO app_settings(key, value) VALUES ('export_columns', ?)", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        }
    }

    func fetchDefaultProjectID() throws -> Int64? {
        try locked {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "SELECT value FROM app_settings WHERE key = 'default_project_id'", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let valuePointer = sqlite3_column_text(statement, 0)
            else { return nil }
            return Int64(String(cString: valuePointer))
        }
    }

    func saveDefaultProjectID(_ projectID: Int64) throws {
        try locked {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "INSERT OR REPLACE INTO app_settings(key, value) VALUES ('default_project_id', ?)", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, String(projectID), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        }
    }

    func exportBackup() throws -> LeoTrackerBackup {
        try locked {
            LeoTrackerBackup(
                version: 1,
                exportedAt: Date(),
                projects: try fetchBackupProjectsLocked(),
                entries: try fetchBackupEntriesLocked(),
                settings: try fetchBackupSettingsLocked()
            )
        }
    }

    func importBackup(_ backup: LeoTrackerBackup) throws {
        try locked {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try execute("DELETE FROM time_entries")
                try execute("DELETE FROM projects")
                try execute("DELETE FROM app_settings")
                for project in backup.projects {
                    try insertBackupProjectLocked(project)
                }
                for entry in backup.entries {
                    try insertBackupEntryLocked(entry)
                }
                for setting in backup.settings {
                    try insertBackupSettingLocked(setting)
                }
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    func deleteEntry(id: Int64) throws {
        try locked {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "DELETE FROM time_entries WHERE id = ?", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, id)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        }
    }

    func stop(id: Int64, endedAt: Date) throws {
        try locked {
            let sql = "UPDATE time_entries SET ended_at = ? WHERE id = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, endedAt.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 2, id)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        }
    }

    func updateEntry(id: Int64, task: String, startedAt: Date, endedAt: Date?) throws {
        try locked {
            let sql = "UPDATE time_entries SET task = ?, started_at = ?, ended_at = ? WHERE id = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, task, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(statement, 2, startedAt.timeIntervalSince1970)
            if let endedAt {
                sqlite3_bind_double(statement, 3, endedAt.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_int64(statement, 4, id)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        }
    }

    func fetch(from start: Date? = nil, projectID: Int64? = nil) throws -> [TimeEntry] {
        try locked {
            let base = "SELECT e.id, e.project_id, p.name, COALESCE(p.hourly_rate, 0), e.task, e.started_at, e.ended_at FROM time_entries e LEFT JOIN projects p ON p.id = e.project_id"
            let sql: String
            switch (start, projectID) {
            case (nil, nil):
                sql = "\(base) ORDER BY e.started_at DESC"
            case (.some, nil):
                sql = "\(base) WHERE e.started_at >= ? ORDER BY e.started_at DESC"
            case (nil, .some):
                sql = "\(base) WHERE e.project_id = ? ORDER BY e.started_at DESC"
            case (.some, .some):
                sql = "\(base) WHERE e.project_id = ? AND e.started_at >= ? ORDER BY e.started_at DESC"
            }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            switch (start, projectID) {
            case (.some(let start), nil):
                sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            case (nil, .some(let projectID)):
                sqlite3_bind_int64(statement, 1, projectID)
            case (.some(let start), .some(let projectID)):
                sqlite3_bind_int64(statement, 1, projectID)
                sqlite3_bind_double(statement, 2, start.timeIntervalSince1970)
            case (nil, nil):
                break
            }
            var items: [TimeEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let endValue = sqlite3_column_type(statement, 6) == SQLITE_NULL
                    ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
                let taskPointer = sqlite3_column_text(statement, 4)
                let task = taskPointer.map { String(cString: $0) } ?? ""
                items.append(TimeEntry(
                    id: sqlite3_column_int64(statement, 0),
                    projectID: sqlite3_column_int64(statement, 1),
                    project: sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? "General",
                    projectHourlyRate: sqlite3_column_double(statement, 3),
                    task: task,
                    startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                    endedAt: endValue
                ))
            }
            return items
        }
    }

    func fetchUnfinishedEntry() throws -> TimeEntry? {
        try fetchUnfinishedEntries(limit: 1).first
    }

    private func fetchUnfinishedEntries(limit: Int) throws -> [TimeEntry] {
        try locked {
            let sql = "SELECT e.id, e.project_id, p.name, COALESCE(p.hourly_rate, 0), e.task, e.started_at, e.ended_at FROM time_entries e LEFT JOIN projects p ON p.id = e.project_id WHERE e.ended_at IS NULL ORDER BY e.started_at DESC LIMIT ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(limit))
            var items: [TimeEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let taskPointer = sqlite3_column_text(statement, 4)
                items.append(TimeEntry(
                    id: sqlite3_column_int64(statement, 0),
                    projectID: sqlite3_column_int64(statement, 1),
                    project: sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? "General",
                    projectHourlyRate: sqlite3_column_double(statement, 3),
                    task: taskPointer.map { String(cString: $0) } ?? "",
                    startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                    endedAt: nil
                ))
            }
            return items
        }
    }

    private func migrateProjects() throws {
        try locked {
            var hasProjectID = false
            var hasHourlyRate = false
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "PRAGMA table_info(time_entries)", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            while sqlite3_step(statement) == SQLITE_ROW {
                if String(cString: sqlite3_column_text(statement, 1)) == "project_id" { hasProjectID = true }
            }
            sqlite3_finalize(statement)
            if !hasProjectID { try execute("ALTER TABLE time_entries ADD COLUMN project_id INTEGER") }
            guard sqlite3_prepare_v2(handle, "PRAGMA table_info(projects)", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            while sqlite3_step(statement) == SQLITE_ROW {
                if String(cString: sqlite3_column_text(statement, 1)) == "hourly_rate" { hasHourlyRate = true }
            }
            sqlite3_finalize(statement)
            if !hasHourlyRate { try execute("ALTER TABLE projects ADD COLUMN hourly_rate REAL NOT NULL DEFAULT 0") }
            try execute("INSERT OR IGNORE INTO projects(name) VALUES ('General')")
            try execute("UPDATE time_entries SET project_id = (SELECT id FROM projects WHERE name = 'General') WHERE project_id IS NULL")
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    private func fetchBackupProjectsLocked() throws -> [BackupProject] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT id, name, hourly_rate FROM projects ORDER BY id", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        var items: [BackupProject] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(BackupProject(
                id: sqlite3_column_int64(statement, 0),
                name: sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "",
                hourlyRate: sqlite3_column_double(statement, 2)
            ))
        }
        return items
    }

    private func fetchBackupEntriesLocked() throws -> [BackupTimeEntry] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT id, project_id, task, started_at, ended_at FROM time_entries ORDER BY id", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        var items: [BackupTimeEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let endedAt = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            items.append(BackupTimeEntry(
                id: sqlite3_column_int64(statement, 0),
                projectID: sqlite3_column_int64(statement, 1),
                task: sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? "",
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                endedAt: endedAt
            ))
        }
        return items
    }

    private func fetchBackupSettingsLocked() throws -> [BackupSetting] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT key, value FROM app_settings ORDER BY key", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        var items: [BackupSetting] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(BackupSetting(
                key: sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "",
                value: sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            ))
        }
        return items
    }

    private func insertBackupProjectLocked(_ project: BackupProject) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "INSERT INTO projects(id, name, hourly_rate) VALUES (?, ?, ?)", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, project.id)
        sqlite3_bind_text(statement, 2, project.name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(statement, 3, max(0, project.hourlyRate))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func insertBackupEntryLocked(_ entry: BackupTimeEntry) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "INSERT INTO time_entries(id, project_id, task, started_at, ended_at) VALUES (?, ?, ?, ?, ?)", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, entry.id)
        sqlite3_bind_int64(statement, 2, entry.projectID)
        sqlite3_bind_text(statement, 3, entry.task, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(statement, 4, entry.startedAt.timeIntervalSince1970)
        if let endedAt = entry.endedAt {
            sqlite3_bind_double(statement, 5, endedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 5)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func insertBackupSettingLocked(_ setting: BackupSetting) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "INSERT INTO app_settings(key, value) VALUES (?, ?)", -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, setting.key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 2, setting.value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private func lastError() -> DatabaseError {
        DatabaseError.execute(String(cString: sqlite3_errmsg(handle)))
    }
}
