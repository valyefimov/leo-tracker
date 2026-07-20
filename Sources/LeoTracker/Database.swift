import CSQLite
import Foundation

enum DatabaseError: LocalizedError {
    case open(String)
    case execute(String)

    var errorDescription: String? {
        switch self {
        case .open(let message): "Не удалось открыть базу: \(message)"
        case .execute(let message): "Ошибка базы данных: \(message)"
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
              task TEXT NOT NULL,
              started_at REAL NOT NULL,
              ended_at REAL
            );
            CREATE INDEX IF NOT EXISTS idx_entries_started_at ON time_entries(started_at DESC);
            """)
    }

    deinit { sqlite3_close(handle) }

    func insert(task: String, startedAt: Date) throws -> Int64 {
        try locked {
            let sql = "INSERT INTO time_entries(task, started_at) VALUES (?, ?)"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, task, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(statement, 2, startedAt.timeIntervalSince1970)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
            return sqlite3_last_insert_rowid(handle)
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

    func fetch(from start: Date? = nil) throws -> [TimeEntry] {
        try locked {
            let sql = start == nil
                ? "SELECT id, task, started_at, ended_at FROM time_entries ORDER BY started_at DESC"
                : "SELECT id, task, started_at, ended_at FROM time_entries WHERE started_at >= ? ORDER BY started_at DESC"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(statement) }
            if let start { sqlite3_bind_double(statement, 1, start.timeIntervalSince1970) }
            var items: [TimeEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let endValue = sqlite3_column_type(statement, 3) == SQLITE_NULL
                    ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                let taskPointer = sqlite3_column_text(statement, 1)
                let task = taskPointer.map { String(cString: $0) } ?? ""
                items.append(TimeEntry(
                    id: sqlite3_column_int64(statement, 0),
                    task: task,
                    startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                    endedAt: endValue
                ))
            }
            return items
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
