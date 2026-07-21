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
            CREATE INDEX IF NOT EXISTS idx_entries_started_at ON time_entries(started_at DESC);
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

    func fetch(from start: Date? = nil) throws -> [TimeEntry] {
        try locked {
            let sql = start == nil
                ? "SELECT e.id, e.project_id, p.name, COALESCE(p.hourly_rate, 0), e.task, e.started_at, e.ended_at FROM time_entries e LEFT JOIN projects p ON p.id = e.project_id ORDER BY e.started_at DESC"
                : "SELECT e.id, e.project_id, p.name, COALESCE(p.hourly_rate, 0), e.task, e.started_at, e.ended_at FROM time_entries e LEFT JOIN projects p ON p.id = e.project_id WHERE e.started_at >= ? ORDER BY e.started_at DESC"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            if let start { sqlite3_bind_double(statement, 1, start.timeIntervalSince1970) }
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

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private func lastError() -> DatabaseError {
        DatabaseError.execute(String(cString: sqlite3_errmsg(handle)))
    }
}
