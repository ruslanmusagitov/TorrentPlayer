//
//  TorrentHistoryEntry.swift
//  TorrentPlayer
//
//  Task #9: SwiftData history of successfully loaded magnets.
//

import Foundation
import SwiftData

@Model
final class TorrentHistoryEntry {
    @Attribute(.unique) var infoHash: String
    var displayName: String
    var magnetURI: String
    var addedAt: Date

    init(
        infoHash: String,
        displayName: String,
        magnetURI: String,
        addedAt: Date = .now
    ) {
        self.infoHash = infoHash
        self.displayName = displayName
        self.magnetURI = magnetURI
        self.addedAt = addedAt
    }

    /// Inserts a new history row, or updates an existing one with the same info hash.
    @MainActor
    static func upsert(
        infoHash: String,
        displayName: String,
        magnetURI: String,
        addedAt: Date = .now,
        in context: ModelContext
    ) throws {
        let hash = infoHash
        let descriptor = FetchDescriptor<TorrentHistoryEntry>(
            predicate: #Predicate { $0.infoHash == hash }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.displayName = displayName
            existing.magnetURI = magnetURI
            existing.addedAt = addedAt
        } else {
            context.insert(
                TorrentHistoryEntry(
                    infoHash: infoHash,
                    displayName: displayName,
                    magnetURI: magnetURI,
                    addedAt: addedAt
                )
            )
        }
        try context.save()
    }

    /// Records history from a successfully loaded torrent (no-op if inputs are incomplete).
    @MainActor
    static func recordLoad(
        magnetURI: String?,
        torrent: ActiveTorrent?,
        in context: ModelContext
    ) throws {
        guard let magnetURI, let torrent else { return }
        try upsert(
            infoHash: torrent.infoHash,
            displayName: torrent.displayName,
            magnetURI: magnetURI,
            in: context
        )
    }

    /// Loads a .torrent file into the engine and records history on success.
    @MainActor
    static func addTorrentFile(
        url: URL,
        using engine: TorrentEngine,
        in context: ModelContext
    ) async throws {
        try await engine.addTorrentFile(url: url)
        if let data = engine.lastTorrentFileData, let torrent = engine.activeTorrent {
            do {
                try TorrentHistoryFileStore.store(data: data, infoHash: torrent.infoHash)
            } catch {
                TPLog.error("history torrent copy failed: \(error.localizedDescription)")
            }
        }
        do {
            try recordLoad(
                magnetURI: engine.lastMagnetURI,
                torrent: engine.activeTorrent,
                in: context
            )
        } catch {
            TPLog.error("history record failed: \(error.localizedDescription)")
        }
    }

    /// Reopens a history row: the stored .torrent copy if present, otherwise the magnet.
    @MainActor
    static func resume(
        _ entry: TorrentHistoryEntry,
        using engine: TorrentEngine,
        in context: ModelContext
    ) async throws {
        if let fileURL = TorrentHistoryFileStore.fileURLIfPresent(for: entry.infoHash) {
            try await addTorrentFile(url: fileURL, using: engine, in: context)
            return
        }
        try await engine.addMagnet(entry.magnetURI)
    }

    static func removeStoredTorrentFile(infoHash: String) {
        TorrentHistoryFileStore.remove(infoHash: infoHash)
    }

    static func removeAllStoredTorrentFiles() {
        TorrentHistoryFileStore.removeAll()
    }
}

enum TorrentHistoryFileStore {
    @TaskLocal static var directoryOverride: URL?

    static func directory() throws -> URL {
        if let directoryOverride {
            try FileManager.default.createDirectory(at: directoryOverride, withIntermediateDirectories: true)
            return directoryOverride
        }
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("TorrentPlayer/HistoryTorrents", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func fileURL(for infoHash: String) throws -> URL {
        try directory().appendingPathComponent("\(infoHash).torrent", isDirectory: false)
    }

    static func fileURLIfPresent(for infoHash: String) -> URL? {
        guard let url = try? fileURL(for: infoHash),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    static func store(data: Data, infoHash: String) throws {
        try data.write(to: try fileURL(for: infoHash), options: .atomic)
    }

    static func remove(infoHash: String) {
        guard let url = try? fileURL(for: infoHash) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func removeAll() {
        guard let dir = try? directory() else { return }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for item in items {
            try? fm.removeItem(at: item)
        }
    }
}
