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
