import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct DBError: Error, LocalizedError {
    public let message: String
    public let code: Int32
    public var errorDescription: String? { message }
    public var isConstraint: Bool { code & 0xff == SQLITE_CONSTRAINT }
}

/// One result row. Missing key == SQL NULL.
public struct Row {
    public let values: [String: Any]
    public subscript(_ key: String) -> Any? { values[key] }
    public func int(_ k: String) -> Int? {
        if let v = values[k] as? Int { return v }
        if let v = values[k] as? Double { return Int(v) }
        return nil
    }
    public func str(_ k: String) -> String? {
        if let v = values[k] as? String { return v }
        if let v = values[k] as? Int { return String(v) }
        return nil
    }
    public func double(_ k: String) -> Double? {
        if let v = values[k] as? Double { return v }
        if let v = values[k] as? Int { return Double(v) }
        return nil
    }
    public func bool(_ k: String) -> Bool { (int(k) ?? 0) != 0 }
}

/// Minimal SQLite wrapper (the system library — no dependencies).
public final class Database {
    public let handle: OpaquePointer
    public let path: String
    private var savepointDepth = 0

    public init(path: String) throws {
        var h: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &h, flags, nil) == SQLITE_OK, let h else {
            let msg = h.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close_v2(h)
            throw DBError(message: "Can't open database: \(msg)", code: SQLITE_CANTOPEN)
        }
        handle = h
        self.path = path
        sqlite3_busy_timeout(h, 3000)
    }

    deinit { sqlite3_close_v2(handle) }

    private func error(_ code: Int32) -> DBError {
        DBError(message: String(cString: sqlite3_errmsg(handle)), code: sqlite3_extended_errcode(handle))
    }

    public func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "SQL error"
            sqlite3_free(err)
            throw DBError(message: msg, code: sqlite3_extended_errcode(handle))
        }
    }

    private func prepare(_ sql: String, _ args: [Any?]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw error(SQLITE_ERROR)
        }
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch a {
            case nil, is NSNull: rc = sqlite3_bind_null(stmt, idx)
            case let v as Int: rc = sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64: rc = sqlite3_bind_int64(stmt, idx, v)
            case let v as Bool: rc = sqlite3_bind_int64(stmt, idx, v ? 1 : 0)
            case let v as Double: rc = sqlite3_bind_double(stmt, idx, v)
            case let v as String: rc = sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            default: rc = sqlite3_bind_text(stmt, idx, "\(a!)", -1, SQLITE_TRANSIENT)
            }
            if rc != SQLITE_OK { sqlite3_finalize(stmt); throw error(rc) }
        }
        return stmt
    }

    /// Run a statement; returns the last inserted rowid.
    @discardableResult
    public func run(_ sql: String, _ args: [Any?] = []) throws -> Int {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw error(rc) }
        return Int(sqlite3_last_insert_rowid(handle))
    }

    public func query(_ sql: String, _ args: [Any?] = []) throws -> [Row] {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        var rows: [Row] = []
        let n = sqlite3_column_count(stmt)
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw error(rc) }
            var dict: [String: Any] = [:]
            for i in 0..<n {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: dict[name] = Int(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT: dict[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT: dict[name] = String(cString: sqlite3_column_text(stmt, i))
                default: break
                }
            }
            rows.append(Row(values: dict))
        }
        return rows
    }

    public func one(_ sql: String, _ args: [Any?] = []) throws -> Row? {
        try query(sql, args).first
    }

    public func scalar(_ sql: String, _ args: [Any?] = []) throws -> Any? {
        try query(sql, args).first?.values.values.first
    }

    /// Atomic block. Nests via savepoints; rolls back on any thrown error.
    @discardableResult
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        savepointDepth += 1
        let name = "sp\(savepointDepth)"
        defer { savepointDepth -= 1 }
        try exec("SAVEPOINT \(name)")
        do {
            let result = try body()
            try exec("RELEASE \(name)")
            return result
        } catch {
            try? exec("ROLLBACK TO \(name)")
            try? exec("RELEASE \(name)")
            throw error
        }
    }

    /// Online copy of the whole database to another file.
    public func backup(to destPath: String) throws {
        var dest: OpaquePointer?
        guard sqlite3_open(destPath, &dest) == SQLITE_OK, let dest else {
            throw DBError(message: "Can't create backup at \(destPath)", code: SQLITE_CANTOPEN)
        }
        defer { sqlite3_close(dest) }
        guard let b = sqlite3_backup_init(dest, "main", handle, "main") else {
            throw DBError(message: String(cString: sqlite3_errmsg(dest)), code: SQLITE_ERROR)
        }
        sqlite3_backup_step(b, -1)
        let rc = sqlite3_backup_finish(b)
        if rc != SQLITE_OK { throw DBError(message: "Backup failed", code: rc) }
    }
}
