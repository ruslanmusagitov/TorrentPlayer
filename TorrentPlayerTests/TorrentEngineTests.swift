//
//  TorrentEngineTests.swift
//  TorrentPlayerTests
//

import Testing
import Foundation
@testable import TorrentPlayer
#if os(macOS) || os(iOS)
import SwiftTorrent
#endif

struct TorrentEngineTests {
    #if os(macOS) || os(iOS)
    @Test func magnetParamsAcceptValidURI() throws {
        let magnet = "magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12&dn=Example"
        let params = try AddTorrentParams.fromMagnet(magnet, savePath: "/tmp")
        #expect(params.magnetLink?.displayName == "Example")
        #expect(params.infoHash?.description == "abcdef1234567890abcdef1234567890abcdef12")
    }

    @Test func resumeDataRoundTripOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TorrentPlayerResume-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let infoHash = try #require(InfoHash(hex: "abcdef1234567890abcdef1234567890abcdef12"))
        var pieces = Bitfield(count: 16)
        pieces.set(0)
        pieces.set(3)
        pieces.set(15)
        let original = ResumeData(
            infoHash: infoHash,
            completedPieces: pieces,
            uploaded: 100,
            downloaded: 2_048,
            savePath: "/tmp/downloads"
        )

        try TorrentEngine.writeResumeData(original, infoHash: infoHash, directory: dir)

        let loaded = try #require(TorrentEngine.loadResumeData(infoHash: infoHash, directory: dir))
        #expect(loaded.infoHash == original.infoHash)
        #expect(loaded.uploaded == 100)
        #expect(loaded.downloaded == 2_048)
        #expect(loaded.savePath == "/tmp/downloads")
        #expect(loaded.completedPieces.get(0))
        #expect(loaded.completedPieces.get(3))
        #expect(loaded.completedPieces.get(15))
        #expect(!loaded.completedPieces.get(1))
    }

    @Test func loadResumeDataReturnsNilWhenMissing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TorrentPlayerResumeMissing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let infoHash = try #require(InfoHash(hex: "abcdef1234567890abcdef1234567890abcdef12"))
        #expect(TorrentEngine.loadResumeData(infoHash: infoHash, directory: dir) == nil)
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
        #expect(item.path == "Interstellar.2014.Main.mkv")
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
        #expect(item.path == "subs/English_Subs.srt")
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
        #expect(torrent.files[0].path == "video/main.mkv")
        #expect(torrent.files[0].name == "main.mkv")
        #expect(torrent.files[1].name == "readme.txt")
        #expect(torrent.formattedTotalSize.contains("MB") || torrent.formattedTotalSize.contains("KB"))
    }

    @Test func diskURLJoinsRelativePathComponents() {
        let base = URL(fileURLWithPath: "/tmp/downloads", isDirectory: true)
        let url = LocalHTTPStreamServer.diskURL(
            downloadsDirectory: base,
            relativePath: "Season 1/Episode.mkv"
        )
        #expect(url.path == "/tmp/downloads/Season 1/Episode.mkv")
    }

    @Test func parseRangeSupportsSuffixAndOpenEnded() {
        #expect(LocalHTTPStreamServer.parseRange("Range: bytes=0-99", fileSize: 1000) == 0...99)
        #expect(LocalHTTPStreamServer.parseRange("Range: bytes=100-", fileSize: 1000) == 100...999)
        #expect(LocalHTTPStreamServer.parseRange("Range: bytes=-50", fileSize: 1000) == 950...999)
    }

    @Test func localHTTPStreamServerServesFullAndPartialContent() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TorrentPlayerHTTP-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("clip.bin")
        let payload = Data((0..<256).map { UInt8($0) })
        try payload.write(to: fileURL)

        let server = LocalHTTPStreamServer(
            fileURL: fileURL,
            fileSize: Int64(payload.count),
            contentType: "application/octet-stream"
        )
        try await server.start()
        defer { server.stop() }
        let streamURL = try #require(server.streamURL)

        let full = try await URLSession.shared.data(from: streamURL)
        #expect(full.0 == payload)
        #expect((full.1 as? HTTPURLResponse)?.statusCode == 200)

        var rangeRequest = URLRequest(url: streamURL)
        rangeRequest.setValue("bytes=10-19", forHTTPHeaderField: "Range")
        let partial = try await URLSession.shared.data(for: rangeRequest)
        #expect(partial.0 == Data(payload[10...19]))
        #expect((partial.1 as? HTTPURLResponse)?.statusCode == 206)
    }

    @Test func streamingByteGateTracksContiguousPrefix() {
        let gate = StreamingByteGate()
        #expect(!gate.isReady(offset: 0, length: 1))
        gate.markReady(through: 100)
        #expect(gate.isReady(offset: 0, length: 100))
        #expect(!gate.isReady(offset: 0, length: 101))
        #expect(gate.isReady(offset: 50, length: 50))
        gate.markReady(through: 50) // non-monotonic lower mark ignored
        #expect(gate.readyThroughOffset == 100)
    }

    @Test func streamingByteGateCoversDisjointTailRange() {
        let gate = StreamingByteGate()
        gate.markReady(through: 2_000_000)
        gate.markReady(range: 1_500_000_000..<1_502_000_000)
        #expect(gate.isReady(offset: 0, length: 2_000_000))
        #expect(gate.isReady(offset: 1_500_000_000, length: 2_000_000))
        #expect(!gate.isReady(offset: 2_000_000, length: 1))
        #expect(!gate.isReady(offset: 1_499_999_999, length: 2))
        #expect(gate.readyThroughOffset == 2_000_000)
    }

    @Test func localHTTPStreamServerStreamsBeforeFullFileReady() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TorrentPlayerHTTPGrow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("grow.bin")
        let totalSize = 1024
        let readyBytes = 300
        // Sparse/growing file: only the leading bytes exist as real data.
        var payload = Data(count: totalSize)
        for i in 0..<readyBytes { payload[i] = UInt8(i % 251) }
        try payload.write(to: fileURL)

        let lock = NSLock()
        var available = readyBytes
        let server = LocalHTTPStreamServer(
            fileURL: fileURL,
            fileSize: Int64(totalSize),
            contentType: "application/octet-stream",
            rangeWaitSeconds: 5,
            chunkSize: 128,
            waitForBytes: { offset, length in
                lock.lock()
                let ready = offset + length <= Int64(available)
                lock.unlock()
                return ready
            }
        )
        try await server.start()
        defer { server.stop() }
        let streamURL = try #require(server.streamURL)

        // Unlock the rest of the file shortly after the client connects.
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            lock.lock()
            available = totalSize
            lock.unlock()
        }

        let (data, response) = try await URLSession.shared.data(from: streamURL)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data.count == totalSize)
        #expect(data.prefix(readyBytes) == payload.prefix(readyBytes))
    }

    @Test @MainActor func preparePlaybackFailsWithoutActiveHandle() async {
        let engine = TorrentEngine(streamingLeadTimeoutSeconds: 1)
        let torrent = TorrentFileFormatting.makeActiveTorrent(
            displayName: "Clip",
            infoHash: "hash",
            totalSize: 1_000,
            fileEntries: [("clip.mp4", 1_000)]
        )
        engine.applyLoadedTorrentForTesting(torrent)
        #expect(engine.selectedFileURL?.lastPathComponent == "clip.mp4")

        await engine.preparePlayback()
        if case .failed = engine.playbackPhase {
            #expect(engine.playbackURL == nil)
        } else {
            Issue.record("Expected failed playback without torrent handle, got \(engine.playbackPhase)")
        }
    }

    @Test @MainActor func isAVPlayerCompatibleRoutesContainers() {
        #expect(TorrentEngine.isAVPlayerCompatible(path: "a/b/clip.mp4"))
        #expect(TorrentEngine.isAVPlayerCompatible(path: "clip.M4V"))
        #expect(TorrentEngine.isAVPlayerCompatible(path: "clip.mov"))
        #expect(!TorrentEngine.isAVPlayerCompatible(path: "film.mkv"))
        #expect(!TorrentEngine.isAVPlayerCompatible(path: "film.avi"))
        #expect(!TorrentEngine.isAVPlayerCompatible(path: "film.webm"))
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

    @Test @MainActor func bootstrapLeavesEngineReadyOnSupportedPlatforms() async {
        #if os(macOS) || os(iOS)
        let engine = TorrentEngine()
        await engine.bootstrap()
        #expect(engine.isOperational)
        #expect(engine.bootStep == .ready)
        #expect(engine.bootProgress == 1)
        #else
        let engine = TorrentEngine()
        await engine.bootstrap()
        #expect(engine.phase == .unsupportedPlatform)
        #expect(engine.bootStep.isTerminal)
        #expect(engine.bootProgress == 1)
        #endif
    }

    @Test @MainActor func addMagnetTimesOutWithoutPeersOnSupportedPlatforms() async {
        #if os(macOS) || os(iOS)
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
        #if os(macOS) || os(iOS)
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

    @Test @MainActor func addMagnetRejectsInvalidURIOnSupportedPlatforms() async {
        #if os(macOS) || os(iOS)
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

    @Test func magnetURIFromTorrentInfoIncludesHashAndTracker() throws {
        #if os(macOS) || os(iOS)
        let data = TorrentFileFixture.makeSingleFileTorrentData()
        let info = try TorrentInfo.parse(from: data)
        let uri = TorrentEngine.magnetURI(from: info)
        #expect(uri.hasPrefix("magnet:?xt=urn:btih:"))
        #expect(uri.contains("tr="))
        #expect(uri.contains("dn=testfile.txt"))
        #else
        #expect(Bool(true))
        #endif
    }

    @Test @MainActor func addTorrentFileLoadsMetadataWithoutNetwork() async throws {
        #if os(macOS) || os(iOS)
        let engine = TorrentEngine()
        await engine.bootstrap()

        let fileURL = try TorrentFileFixture.writeTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        try await engine.addTorrentFile(url: fileURL)

        guard case let .loaded(torrent) = engine.phase else {
            Issue.record("Expected loaded phase after torrent file, got \(engine.phase)")
            return
        }
        #expect(torrent.displayName == TorrentFileFixture.fileName)
        #expect(torrent.files.count == 1)
        #expect(torrent.files[0].path == TorrentFileFixture.fileName)
        #expect(engine.lastMagnetURI?.contains("xt=urn:btih:") == true)
        #expect(engine.lastMagnetURI?.contains("tr=") == true)
        #else
        #expect(Bool(true))
        #endif
    }

    @Test @MainActor func addTorrentFileRejectsInvalidDataWhileKeepingPreviousTorrent() async throws {
        #if os(macOS) || os(iOS)
        let engine = TorrentEngine()
        await engine.bootstrap()

        let previous = TorrentFileFormatting.makeActiveTorrent(
            displayName: "Previous",
            infoHash: "prevhash",
            totalSize: 1_000,
            fileEntries: [("main.mkv", 1_000)]
        )
        engine.applyLoadedTorrentForTesting(previous)

        let fileURL = try TorrentFileFixture.writeTempFile(data: Data("not-a-torrent".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        await #expect(throws: TorrentEngineError.invalidTorrentFile) {
            try await engine.addTorrentFile(url: fileURL)
        }

        if case let .error(message) = engine.phase {
            #expect(message == TorrentEngineError.invalidTorrentFile.localizedDescription)
        } else {
            Issue.record("Expected error phase after invalid torrent file, got \(engine.phase)")
        }
        #expect(engine.activeTorrent == previous)
        #expect(engine.selectedFileID == previous.defaultSelectedFileID)
        #else
        #expect(Bool(true))
        #endif
    }

    @Test @MainActor func addTorrentFileRejectsNonFileURLWithoutReadingNetwork() async {
        #if os(macOS) || os(iOS)
        let engine = TorrentEngine()
        let remote = URL(string: "https://example.com/video.torrent")!
        await #expect(throws: TorrentEngineError.invalidTorrentFile) {
            try await engine.addTorrentFile(url: remote)
        }
        if case let .error(message) = engine.phase {
            #expect(message == TorrentEngineError.invalidTorrentFile.localizedDescription)
        } else {
            Issue.record("Expected error phase for remote torrent URL, got \(engine.phase)")
        }
        #else
        #expect(Bool(true))
        #endif
    }
}

@Suite(.serialized)
@MainActor
struct IncomingTorrentFilesTests {
    @Test func isTorrentFileURLRequiresLocalFile() {
        #expect(IncomingTorrentFiles.isTorrentFileURL(URL(fileURLWithPath: "/tmp/clip.torrent")))
        #expect(!IncomingTorrentFiles.isTorrentFileURL(URL(fileURLWithPath: "/tmp/clip.mp4")))
        #expect(!IncomingTorrentFiles.isTorrentFileURL(URL(string: "https://example.com/clip.torrent")!))
        #expect(!IncomingTorrentFiles.isTorrentFileURL(URL(string: "magnet:?xt=urn:btih:abc")!))
    }

    @Test func handleKeepsOnlyTheLatestTorrent() {
        defer { _ = IncomingTorrentFiles.takeLatest() }

        IncomingTorrentFiles.enqueueLatest([
            URL(fileURLWithPath: "/tmp/first.torrent"),
            URL(fileURLWithPath: "/tmp/readme.txt"),
            URL(fileURLWithPath: "/tmp/second.torrent"),
        ])
        IncomingTorrentFiles.enqueueLatest([
            URL(string: "https://example.com/remote.torrent")!,
            URL(fileURLWithPath: "/tmp/third.torrent"),
        ])

        #expect(IncomingTorrentFiles.hasPending)
        #expect(IncomingTorrentFiles.takeLatest() == URL(fileURLWithPath: "/tmp/third.torrent"))
        #expect(!IncomingTorrentFiles.hasPending)
        #expect(IncomingTorrentFiles.takeLatest() == nil)
    }

    @Test func persistDroppedFileCopiesReadableTorrent() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("drop-source-\(UUID().uuidString).torrent")
        try Data("torrent".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let persisted = try IncomingTorrentFiles.persistDroppedFile(source)
        defer { try? FileManager.default.removeItem(at: persisted) }

        #expect(IncomingTorrentFiles.isTorrentFileURL(persisted))
        #expect(persisted != source)
        #expect(try Data(contentsOf: persisted) == Data("torrent".utf8))
    }

    @Test func addTorrentFileDeletesIncomingStagingCopy() async throws {
        #if os(macOS) || os(iOS)
        let engine = TorrentEngine()
        await engine.bootstrap()

        let fixture = try TorrentFileFixture.writeTempFile()
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }

        let staged = try IncomingTorrentFiles.persistDroppedFile(fixture)
        try await engine.addTorrentFile(url: staged)
        #expect(!FileManager.default.fileExists(atPath: staged.path))
        #else
        #expect(Bool(true))
        #endif
    }

    @Test func enqueueLatestDeletesReplacedStagingCopy() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("drop-replace-\(UUID().uuidString).torrent")
        try Data("torrent".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let first = try IncomingTorrentFiles.persistDroppedFile(source)
        let second = try IncomingTorrentFiles.persistDroppedFile(source)
        defer {
            IncomingTorrentFiles.discardLatest()
            IncomingTorrentFiles.removeConsumedCopyIfNeeded(first)
            IncomingTorrentFiles.removeConsumedCopyIfNeeded(second)
        }

        IncomingTorrentFiles.enqueueLatest([first])
        IncomingTorrentFiles.enqueueLatest([second])

        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(IncomingTorrentFiles.takeLatest() == second)
    }

    @Test func addTorrentFileKeepsStagingCopyWhenLoadFails() async throws {
        #if os(macOS) || os(iOS)
        let engine = TorrentEngine()
        await engine.bootstrap()

        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("drop-invalid-\(UUID().uuidString).torrent")
        try Data("not-a-torrent".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let staged = try IncomingTorrentFiles.persistDroppedFile(source)
        defer { IncomingTorrentFiles.removeConsumedCopyIfNeeded(staged) }

        await #expect(throws: TorrentEngineError.invalidTorrentFile) {
            try await engine.addTorrentFile(url: staged)
        }
        #expect(FileManager.default.fileExists(atPath: staged.path))
        #else
        #expect(Bool(true))
        #endif
    }
}

#if os(macOS) || os(iOS)
private enum TorrentFileFixture {
    static let announceURL = "skip://tracker.invalid/announce"
    static let fileName = "testfile.txt"

    static func makeSingleFileTorrentData() -> Data {
        let encoder = BencodeEncoder()
        let pieces = Data(repeating: 0xAB, count: 20)
        let info: BencodeValue = .dictionary([
            (key: Data("length".utf8), value: .integer(1024)),
            (key: Data("name".utf8), value: .string(Data(fileName.utf8))),
            (key: Data("piece length".utf8), value: .integer(262144)),
            (key: Data("pieces".utf8), value: .string(pieces)),
        ])
        let root: BencodeValue = .dictionary([
            (key: Data("announce".utf8), value: .string(Data(announceURL.utf8))),
            (key: Data("info".utf8), value: info),
        ])
        return encoder.encode(root)
    }

    static func writeTempFile(data: Data = TorrentFileFixture.makeSingleFileTorrentData()) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TorrentPlayerTorrent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("fixture.torrent")
        try data.write(to: url)
        return url
    }
}
#endif
