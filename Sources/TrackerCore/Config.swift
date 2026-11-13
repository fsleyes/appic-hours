import Foundation

/// Where things live on disk.
///
/// The app (bundle and project folder) never holds client data. The config file in
/// ~/Library/Application Support stores *only paths*.
public struct AppConfig: Codable, Equatable {
    public var dataDir: String?
    public var exportDir: String?

    enum CodingKeys: String, CodingKey {
        case dataDir = "data_dir"
        case exportDir = "export_dir"
    }

    public init(dataDir: String? = nil, exportDir: String? = nil) {
        self.dataDir = dataDir
        self.exportDir = exportDir
    }

    public static let appName = "APPIC Hours Tracker"
    public static let envDataDir = "APPIC_TRACKER_DATA"
    public static let dbName = "tracker.db"
    public static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(appName)")
    }
    public static var configFile: URL { configDir.appendingPathComponent("config.json") }
    public static var defaultDataDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/APPIC Tracker Data")
    }

    /// Folders that must never contain client data (the app bundle and its source folder).
    public static var forbiddenDirs: [URL] {
        var dirs = [Bundle.main.bundleURL]
        if let p = Bundle.main.object(forInfoDictionaryKey: "ProjectDirectory") as? String { dirs.append(URL(fileURLWithPath: p)) }
        return dirs
    }

    public var isConfigured: Bool {
        ProcessInfo.processInfo.environment[Self.envDataDir] != nil || dataDir != nil
    }

    public var dataURL: URL {
        if let env = ProcessInfo.processInfo.environment[Self.envDataDir] {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: ((dataDir ?? Self.defaultDataDir.path) as NSString).expandingTildeInPath)
    }
    public var dbURL: URL { dataURL.appendingPathComponent(Self.dbName) }
    public var backupURL: URL { dataURL.appendingPathComponent("backups") }
    public var exportURL: URL {
        if let e = exportDir { return URL(fileURLWithPath: (e as NSString).expandingTildeInPath) }
        return dataURL.appendingPathComponent("exports")
    }

    public func ensureDirs() throws {
        for u in [dataURL, backupURL, exportURL] {
            try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        }
    }

    public struct DataDirError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Reject folders inside the app's own folders.
    @discardableResult
    public static func validate(_ url: URL, forbidden: [URL] = forbiddenDirs) throws -> URL {
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        for f in forbidden {
            let fp = f.standardizedFileURL.resolvingSymlinksInPath().path
            if p == fp || p.hasPrefix(fp + "/") {
                throw DataDirError(message: "Choose a folder outside the app (\(fp)) so the app files never contain client information.")
            }
        }
        return url.standardizedFileURL
    }

    public static func load(from file: URL = configFile) -> AppConfig {
        guard let data = try? Data(contentsOf: file),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else { return AppConfig() }
        return cfg
    }

    public func save(to file: URL = configFile) throws {
        if let d = dataDir { try Self.validate(URL(fileURLWithPath: d)) }
        if let e = exportDir { try Self.validate(URL(fileURLWithPath: e)) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: file, options: .atomic)
    }
}
