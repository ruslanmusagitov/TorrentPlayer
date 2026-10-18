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

    @Test func recordLoadPersistsMagnetDerivedFromTorrentFile() throws {
        let context = try makeContext()
        let magnet =
            "magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12"
            + "&dn=testfile.txt&tr=skip://tracker.invalid/announce"
        try TorrentHistoryEntry.recordLoad(
            magnetURI: magnet,
            torrent: ActiveTorrent(
                displayName: "testfile.txt",
                infoHash: "abcdef1234567890abcdef1234567890abcdef12",
                totalSize: 1024,
                files: []
            ),
            in: context
        )

        let entries = try context.fetch(FetchDescriptor<TorrentHistoryEntry>())
        #expect(entries.count == 1)
        #expect(entries[0].displayName == "testfile.txt")
        #expect(entries[0].magnetURI.contains("xt=urn:btih:"))
        #expect(entries[0].magnetURI.contains("tr="))
    }

    @Test func fileURLIfPresentDoesNotCreateDirectory() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("torrent-history-missing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        TorrentHistoryFileStore.$directoryOverride.withValue(dir) {
            #expect(TorrentHistoryFileStore.fileURLIfPresent(for: "missing") == nil)
            #expect(!FileManager.default.fileExists(atPath: dir.path))
        }
    }

    @Test func storesTorrentFileForLookupAndDelete() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("torrent-history-files-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try TorrentHistoryFileStore.$directoryOverride.withValue(dir) {
            let data = Data("torrent-bytes".utf8)
            try TorrentHistoryFileStore.store(data: data, infoHash: "abc123")
            let url = try #require(TorrentHistoryFileStore.fileURLIfPresent(for: "abc123"))
            #expect(try Data(contentsOf: url) == data)

            TorrentHistoryFileStore.remove(infoHash: "abc123")
            #expect(TorrentHistoryFileStore.fileURLIfPresent(for: "abc123") == nil)
        }
    }

    @Test func addTorrentFileKeepsCopyUsedByHistoryResume() async throws {
        #if os(macOS) || os(iOS)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("torrent-history-files-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try await TorrentHistoryFileStore.$directoryOverride.withValue(dir) {
            let engine = TorrentEngine()
            await engine.bootstrap()
            let context = try makeContext()
            let fileURL = try TorrentFileFixture.writeTempFile()
            defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
            let original = try Data(contentsOf: fileURL)

            try await TorrentHistoryEntry.addTorrentFile(url: fileURL, using: engine, in: context)

            let entries = try context.fetch(FetchDescriptor<TorrentHistoryEntry>())
            #expect(entries.count == 1)
            let stored = try #require(TorrentHistoryFileStore.fileURLIfPresent(for: entries[0].infoHash))
            #expect(try Data(contentsOf: stored) == original)
            let addedAt = entries[0].addedAt
            let magnetURI = entries[0].magnetURI

            try FileManager.default.removeItem(at: fileURL)

            let engine2 = TorrentEngine()
            await engine2.bootstrap()
            try await TorrentHistoryEntry.resume(entries[0], using: engine2)
            guard case let .loaded(torrent) = engine2.phase else {
                Issue.record("Expected loaded phase after history resume, got \(engine2.phase)")
                return
            }
            #expect(torrent.displayName == TorrentFileFixture.fileName)
            #expect(torrent.infoHash == entries[0].infoHash)
            // Resume reopens the row without bumping it or rewriting its magnet.
            #expect(entries[0].addedAt == addedAt)
            #expect(entries[0].magnetURI == magnetURI)
            #expect(FileManager.default.fileExists(atPath: stored.path))
        }
        #else
        #expect(Bool(true))
        #endif
    }

    @Test func displayHelpersMatchDesignConventions() {
        let video = TorrentHistoryEntry(
            infoHash: "abcdef1234567890abcdef1234567890abcdef12",
            displayName: "Movie.mkv",
            magnetURI: "magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12"
        )
        #expect(video.shortID == "ABCDEF12")
        #expect(video.badgeLabel == "VIDEO_MKV")

        let other = TorrentHistoryEntry(
            infoHash: "deadbeef",
            displayName: "Archive",
            magnetURI: "magnet:?xt=urn:btih:deadbeef"
        )
        #expect(other.shortID == "DEADBEEF")
        #expect(other.badgeLabel == "TORRENT")
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([TorrentHistoryEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
