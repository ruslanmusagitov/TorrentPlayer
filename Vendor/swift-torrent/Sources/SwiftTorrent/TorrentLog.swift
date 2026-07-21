//
//  TorrentLog.swift
//  SwiftTorrent
//
//  Unified logging for Console.app (subsystem SwiftTorrent) and optional file tail.
//

import Foundation
import OSLog

/// Debug logging for the torrent engine. Enable a log file from the app via `enableFileLogging(at:)`.
public enum TorrentLog: Sendable {
    private static let peerLogger = Logger(subsystem: "SwiftTorrent", category: "Peer")
    private static let pieceLogger = Logger(subsystem: "SwiftTorrent", category: "Piece")
    private static let sessionLogger = Logger(subsystem: "SwiftTorrent", category: "Session")
    private static let storageLogger = Logger(subsystem: "SwiftTorrent", category: "Storage")

    nonisolated(unsafe) private static var fileHandle: FileHandle?
    nonisolated(unsafe) private static var fileURL: URL?
    private static let lock = NSLock()

    /// Append UTF-8 lines to this file (created if needed). Pass nil to disable.
    public static func enableFileLogging(at url: URL?) {
        lock.lock()
        defer { lock.unlock() }
        try? fileHandle?.close()
        fileHandle = nil
        fileURL = url
        guard let url else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: url)
        fileHandle?.seekToEndOfFile()
        let header = "——— TorrentLog started \(ISO8601DateFormatter().string(from: Date())) ———\n"
        fileHandle?.write(Data(header.utf8))
    }

    public static var currentLogFileURL: URL? {
        lock.lock(); defer { lock.unlock() }
        return fileURL
    }

    public static func peer(_ message: String) {
        peerLogger.info("\(message, privacy: .public)")
        append(category: "Peer", message)
    }

    public static func piece(_ message: String) {
        pieceLogger.info("\(message, privacy: .public)")
        append(category: "Piece", message)
    }

    public static func session(_ message: String) {
        sessionLogger.info("\(message, privacy: .public)")
        append(category: "Session", message)
    }

    public static func storage(_ message: String) {
        storageLogger.info("\(message, privacy: .public)")
        append(category: "Storage", message)
    }

    /// App-side categories writing into the same file.
    public static func app(_ category: String, _ message: String) {
        Logger(subsystem: "TorrentPlayer", category: category)
            .info("\(message, privacy: .public)")
        append(category: category, message)
    }

    public static func error(_ category: String, _ message: String) {
        Logger(subsystem: "SwiftTorrent", category: category)
            .error("\(message, privacy: .public)")
        append(category: category, "ERROR " + message)
    }

    private static func append(category: String, _ message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let handle = fileHandle else { return }
        let line = "\(timestamp()) [\(category)] \(message)\n"
        handle.write(Data(line.utf8))
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
