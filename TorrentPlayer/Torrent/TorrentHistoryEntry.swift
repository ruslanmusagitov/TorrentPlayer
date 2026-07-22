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
}
