import Foundation
import os

/// File-backed logger with rotation. Mirrors lines to the unified log via os.Logger.
final class Logger: @unchecked Sendable {
    static let shared = Logger()

    private let logDir: URL
    private let logFile: URL
    private let queue = DispatchQueue(label: "synklok.logger", qos: .utility)
    private let maxBytes = 1_000_000
    private let osLog = os.Logger(subsystem: "app.synklok", category: "sync")

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private init() {
        let logs = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Synklok", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        self.logDir = logs
        self.logFile = logs.appendingPathComponent("sync.log")
    }

    var logFileURL: URL { logFile }
    var logDirectoryURL: URL { logDir }

    func info(_ msg: String)  { osLog.info("\(msg, privacy: .public)");    write(msg, level: "INFO") }
    func warn(_ msg: String)  { osLog.warning("\(msg, privacy: .public)"); write(msg, level: "WARN") }
    func error(_ msg: String) { osLog.error("\(msg, privacy: .public)");   write(msg, level: "ERROR") }

    private func write(_ msg: String, level: String) {
        let stamp = Self.formatter.string(from: Date())
        let line = "[\(stamp)] [\(level)] \(msg)\n"
        queue.async { [self] in
            rotateIfNeeded()
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let h = try? FileHandle(forWritingTo: logFile) {
                    defer { try? h.close() }
                    try? h.seekToEnd()
                    try? h.write(contentsOf: data)
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
              let size  = attrs[.size] as? Int,
              size > maxBytes else { return }

        let fm = FileManager.default
        // Drop the oldest, shift sync.log.N → sync.log.N+1, keep up to 5 archives.
        try? fm.removeItem(at: logDir.appendingPathComponent("sync.log.5"))
        for i in stride(from: 4, through: 1, by: -1) {
            let from = logDir.appendingPathComponent("sync.log.\(i)")
            let to   = logDir.appendingPathComponent("sync.log.\(i + 1)")
            if fm.fileExists(atPath: from.path) {
                try? fm.moveItem(at: from, to: to)
            }
        }
        try? fm.moveItem(at: logFile, to: logDir.appendingPathComponent("sync.log.1"))
    }
}
