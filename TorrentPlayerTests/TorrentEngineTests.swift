//
//  TorrentEngineTests.swift
//  TorrentPlayerTests
//

import Testing
import Foundation
@testable import TorrentPlayer
#if os(macOS)
import SwiftTorrent
#endif

struct TorrentEngineTests {
    #if os(macOS)
    @Test func magnetParamsAcceptValidURI() throws {
        let magnet = "magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12&dn=Example"
        let params = try AddTorrentParams.fromMagnet(magnet, savePath: "/tmp")
        #expect(params.magnetLink?.displayName == "Example")
        #expect(params.infoHash?.description == "abcdef1234567890abcdef1234567890abcdef12")
    }

    @Test func magnetParamsRejectInvalidURI() {
        #expect(throws: AddTorrentError.self) {
            _ = try AddTorrentParams.fromMagnet("not-a-magnet", savePath: "/tmp")
        }
    }

    @Test func realWorldMagnetParses() throws {
        let magnet = "magnet:?xt=urn:btih:6950F7068A75E63A8AD6C2B1AA6B63E10B18B51D&tr=http%3A%2F%2Fbt.t-ru.org%2Fann%3Fmagnet&dn=Citizen"
        let params = try AddTorrentParams.fromMagnet(magnet, savePath: "/tmp")
        #expect(params.infoHash != nil)
        #expect(params.magnetLink?.trackers.isEmpty == false)
    }

    @Test func httpTrackerAnnounceReturnsPeers() async throws {
        let hash = try #require(InfoHash(hex: "6950F7068A75E63A8AD6C2B1AA6B63E10B18B51D"))
        let peerID = Data("-TP0001-012345678901".utf8)
        let tracker = HTTPTracker(announceURL: "http://bt.t-ru.org/ann?magnet")
        let response = try await tracker.announce(
            params: AnnounceParams(
                infoHash: hash,
                peerID: peerID,
                port: 6881,
                left: 1,
                event: "started"
            )
        )
        #expect(!response.peers.isEmpty)
    }

    /// Live network: magnet → tracker peers → metadata → file list.
    /// Requires outbound HTTP/TCP. Times out after 10s if metadata never arrives.
    @Test @MainActor
    func citizenVigilanteMagnetLoadsFileList() async throws {
        // Exact magnet from issue #4 manual verification (Citizen Vigilante / torrents.ru).
        let magnet =
            "magnet:?xt=urn:btih:6950F7068A75E63A8AD6C2B1AA6B63E10B18B51D"
            + "&tr=http%3A%2F%2Fbt.t-ru.org%2Fann%3Fmagnet"
            + "&dn=Гражданин-мститель%20%2F%20Citizen%20Vigilante%20(Уве%20Болл%20%2F%20Uwe%20Boll)%20%5B2026%2C%20Хорватия%2C%20Германия%2C%20боевик%2C%20триллер%2C%20WEB-DLRip-AVC%5D%20MVO%20(TVShows)%20%2B%20Sub%20Rus%2C%20Eng%2C%20"

        let engine = TorrentEngine(metadataTimeoutSeconds: 10)
        await engine.bootstrap()
        #expect(engine.isOperational)

        try await engine.addMagnet(magnet)

        let torrent = try #require(engine.activeTorrent)
        #expect(torrent.infoHash == "6950f7068a75e63a8ad6c2b1aa6b63e10b18b51d")
        #expect(!torrent.files.isEmpty)
        #expect(torrent.totalSize > 0)
        #expect(torrent.files.contains { $0.size > 0 })
        #expect(engine.selectedFileID == torrent.defaultSelectedFileID)
        if !torrent.videoFiles.isEmpty {
            #expect(engine.selectedFile != nil)
        }
        if case let .loaded(loaded) = engine.phase {
            #expect(loaded.files.count == torrent.files.count)
        } else {
            Issue.record("Expected loaded phase, got \(engine.phase)")
        }
    }
    #endif

    @Test func fileNameUsesLastPathComponent() {
        #expect(TorrentFileFormatting.fileName(from: "Season 1/Episode.mkv") == "Episode.mkv")
        #expect(TorrentFileFormatting.fileName(from: "single.mkv") == "single.mkv")
    }

    @Test func makeFileItemBuildsDetailWithSizeAndKind() {
        let item = TorrentFileFormatting.makeFileItem(
            index: 0,
            path: "Interstellar.2014.Main.mkv",
            length: 46_500_000_000
        )
        #expect(item.id == 0)
        #expect(item.name == "Interstellar.2014.Main.mkv")
        #expect(item.size == 46_500_000_000)
        #expect(item.detail.contains("GB"))
        #expect(item.detail.contains("Video/MKV"))
        #expect(item.isVideo)
    }

    @Test func makeFileItemMarksSubtitlesAsNonVideo() {
        let item = TorrentFileFormatting.makeFileItem(
            index: 1,
            path: "subs/English_Subs.srt",
            length: 156_000
        )
        #expect(item.name == "English_Subs.srt")
        #expect(item.detail.contains("Text/SRT"))
        #expect(!item.isVideo)
    }

    @Test func makeActiveTorrentMapsAllEntries() {
        let torrent = TorrentFileFormatting.makeActiveTorrent(
            displayName: "Example Release",
            infoHash: "abc123",
            totalSize: 1_000_000,
            fileEntries: [
                ("video/main.mkv", 900_000),
                ("readme.txt", 100_000),
            ]
        )
        #expect(torrent.displayName == "Example Release")
        #expect(torrent.infoHash == "abc123")
        #expect(torrent.totalSize == 1_000_000)
        #expect(torrent.files.count == 2)
        #expect(torrent.files[0].name == "main.mkv")
        #expect(torrent.files[1].name == "readme.txt")
        #expect(torrent.formattedTotalSize.contains("MB") || torrent.formattedTotalSize.contains("KB"))
    }

    @Test func videoFilesFiltersNonVideoEntries() {
        let torrent = TorrentFileFormatting.makeActiveTorrent(
            displayName: "Mixed",
            infoHash: "hash",
            totalSize: 2_000_000,
            fileEntries: [
                ("readme.txt", 100),
                ("main.mkv", 1_000_000),
                ("subs.srt", 200),
                ("trailer.mp4", 500_000),
                ("poster.jpg", 50_000),
            ]
        )
        #expect(torrent.files.count == 5)
        #expect(torrent.videoFiles.map(\.name) == ["main.mkv", "trailer.mp4"])
        #expect(torrent.defaultSelectedFileID == 1)
    }

    @Test func defaultSelectedFileIDIsNilWithoutVideos() {
        let torrent = TorrentFileFormatting.makeActiveTorrent(
            displayName: "Docs Only",
            infoHash: "hash",
            totalSize: 300,
            fileEntries: [
                ("readme.txt", 100),
                ("info.nfo", 200),
            ]
        )
        #expect(torrent.videoFiles.isEmpty)
        #expect(torrent.defaultSelectedFileID == nil)
    }

    @Test @MainActor func selectFileAcceptsOnlyVideoIDs() {
        let engine = TorrentEngine()
        let torrent = TorrentFileFormatting.makeActiveTorrent(
            displayName: "Mixed",
            infoHash: "hash",
            totalSize: 1_500_000,
            fileEntries: [
                ("main.mkv", 1_000_000),
                ("subs.srt", 200),
                ("extra.mp4", 500_000),
            ]
        )
        engine.applyLoadedTorrentForTesting(torrent)

        #expect(engine.selectedFileID == 0)
        #expect(engine.selectedFile?.name == "main.mkv")

        engine.selectFile(id: 1)
        #expect(engine.selectedFileID == 0)

        engine.selectFile(id: 2)
        #expect(engine.selectedFileID == 2)
        #expect(engine.selectedFile?.name == "extra.mp4")

        engine.selectFile(id: 99)
        #expect(engine.selectedFileID == 2)
    }

    @Test @MainActor func bootstrapLeavesEngineReadyOnMacOS() async {
        #if os(macOS)
        let engine = TorrentEngine()
        await engine.bootstrap()
        #expect(engine.isOperational)
        #else
        let engine = TorrentEngine()
        await engine.bootstrap()
        #expect(engine.phase == .unsupportedPlatform)
        #endif
    }

    @Test @MainActor func addMagnetTimesOutWithoutPeersOnMacOS() async {
        #if os(macOS)
        let engine = TorrentEngine(metadataTimeoutSeconds: 1)
        await engine.bootstrap()

        let magnet = "magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12&dn=Example"
        await #expect(throws: TorrentEngineError.metadataTimeout) {
            try await engine.addMagnet(magnet)
        }
        if case .error = engine.phase {
            #expect(engine.isOperational)
        } else {
            Issue.record("Expected error phase after metadata timeout, got \(engine.phase)")
        }
        #expect(engine.activeTorrent == nil)
        #else
        #expect(Bool(true))
        #endif
    }

    @Test @MainActor func addMagnetTimeoutSurfacesErrorWhileKeepingPreviousTorrent() async {
        #if os(macOS)
        let engine = TorrentEngine(metadataTimeoutSeconds: 1)
        await engine.bootstrap()

        let previous = TorrentFileFormatting.makeActiveTorrent(
            displayName: "Previous",
            infoHash: "prevhash",
            totalSize: 1_000,
            fileEntries: [("main.mkv", 1_000)]
        )
        engine.applyLoadedTorrentForTesting(previous)

        let magnet = "magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12&dn=Example"
        await #expect(throws: TorrentEngineError.metadataTimeout) {
            try await engine.addMagnet(magnet)
        }

        if case let .error(message) = engine.phase {
            #expect(message == TorrentEngineError.metadataTimeout.localizedDescription)
        } else {
            Issue.record("Expected error phase after second magnet timeout, got \(engine.phase)")
        }
        #expect(engine.activeTorrent == previous)
        #expect(engine.selectedFileID == previous.defaultSelectedFileID)
        #else
        #expect(Bool(true))
        #endif
    }

    @Test @MainActor func addMagnetRejectsInvalidURIOnMacOS() async {
        #if os(macOS)
        let engine = TorrentEngine()
        await engine.bootstrap()

        await #expect(throws: AddTorrentError.self) {
            try await engine.addMagnet("not-a-magnet")
        }
        if case .error = engine.phase {
            #expect(engine.isOperational)
        } else {
            Issue.record("Expected error phase after invalid magnet, got \(engine.phase)")
        }
        #else
        #expect(Bool(true))
        #endif
    }
}
