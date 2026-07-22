//
//  TorrentHistoryEntryTests.swift
//  TorrentPlayerTests
//
//  Task #9: SwiftData history persistence.
//

import Foundation
import SwiftData
import Testing
@testable import TorrentPlayer

@MainActor
struct TorrentHistoryEntryTests {
    @Test func upsertInsertsNewEntry() throws {
        let context = try makeContext()
        try TorrentHistoryEntry.upsert(
            infoHash: "abc123",
            displayName: "Example",
            magnetURI: "magnet:?xt=urn:btih:abc123&dn=Example",
            in: context
        )

        let entries = try context.fetch(FetchDescriptor<TorrentHistoryEntry>())
        #expect(entries.count == 1)
        #expect(entries[0].infoHash == "abc123")
        #expect(entries[0].displayName == "Example")
        #expect(entries[0].magnetURI.contains("abc123"))
    }

    @Test func upsertUpdatesExistingInfoHash() throws {
        let context = try makeContext()
        let firstAdded = Date(timeIntervalSince1970: 1_700_000_000)
        try TorrentHistoryEntry.upsert(
            infoHash: "abc123",
            displayName: "Old Name",
            magnetURI: "magnet:?xt=urn:btih:abc123&dn=Old",
            addedAt: firstAdded,
            in: context
        )

        let secondAdded = Date(timeIntervalSince1970: 1_700_000_100)
        try TorrentHistoryEntry.upsert(
            infoHash: "abc123",
            displayName: "New Name",
            magnetURI: "magnet:?xt=urn:btih:abc123&dn=New",
            addedAt: secondAdded,
            in: context
        )

        let entries = try context.fetch(FetchDescriptor<TorrentHistoryEntry>())
        #expect(entries.count == 1)
        #expect(entries[0].displayName == "New Name")
        #expect(entries[0].magnetURI.contains("dn=New"))
        #expect(entries[0].addedAt == secondAdded)
    }

    @Test func recordLoadPersistsBetweenContainers() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("torrent-history-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let schema = Schema([TorrentHistoryEntry.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            try TorrentHistoryEntry.recordLoad(
                magnetURI: "magnet:?xt=urn:btih:deadbeef&dn=Persist",
                torrent: ActiveTorrent(
                    displayName: "Persist Me",
                    infoHash: "deadbeef",
                    totalSize: 42,
                    files: []
                ),
                in: context
            )
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let entries = try context.fetch(
                FetchDescriptor<TorrentHistoryEntry>(
                    sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
                )
            )
            #expect(entries.count == 1)
            #expect(entries[0].infoHash == "deadbeef")
            #expect(entries[0].displayName == "Persist Me")
            #expect(entries[0].magnetURI.contains("Persist"))
        }
    }

    @Test func recordLoadIgnoresIncompleteInput() throws {
        let context = try makeContext()
        try TorrentHistoryEntry.recordLoad(magnetURI: nil, torrent: nil, in: context)
        try TorrentHistoryEntry.recordLoad(
            magnetURI: "magnet:?xt=urn:btih:abc",
            torrent: nil,
            in: context
        )

        let entries = try context.fetch(FetchDescriptor<TorrentHistoryEntry>())
        #expect(entries.isEmpty)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([TorrentHistoryEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
