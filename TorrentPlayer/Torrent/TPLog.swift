//
//  TPLog.swift
//  TorrentPlayer
//
//  App-level logging (Console + shared file with SwiftTorrent).
//

import Foundation
import OSLog
#if os(macOS) || os(iOS)
import SwiftTorrent
#endif

enum TPLog {
    /// Starts file logging under Application Support/TorrentPlayer/Logs/debug.log
    @discardableResult
    static func bootstrapFileLogging() -> URL? {
        #if os(macOS) || os(iOS)
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("TorrentPlayer/Logs", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let url = base.appendingPathComponent("debug.log")
            TorrentLog.enableFileLogging(at: url)
            engine("File logging → \(url.path)")
            return url
        } catch {
            Logger(subsystem: "TorrentPlayer", category: "Engine")
                .error("Failed to enable file logging: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        #else
        return nil
        #endif
    }

    static var logFileURL: URL? {
        #if os(macOS) || os(iOS)
        TorrentLog.currentLogFileURL
        #else
        nil
        #endif
    }

    static func engine(_ message: String) {
        #if os(macOS) || os(iOS)
        TorrentLog.app("Engine", message)
        #endif
    }

    static func playback(_ message: String) {
        #if os(macOS) || os(iOS)
        TorrentLog.app("Playback", message)
        #endif
    }

    static func http(_ message: String) {
        #if os(macOS) || os(iOS)
        TorrentLog.app("HTTP", message)
        #endif
    }

    static func error(_ message: String) {
        #if os(macOS) || os(iOS)
        TorrentLog.error("Engine", message)
        #endif
    }
}
