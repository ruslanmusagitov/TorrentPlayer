//
//  TorrentEngine.swift
//  TorrentPlayer
//
//  Task #3: torrent session on macOS (SwiftTorrent SPM).
//  Task #4: metadata fetch and file list.
//  Task #5: video file selection.
//  Task #6: sequential download of selected file.
//  Task #7: local HTTP stream bridge → AVPlayer.
//  Task #8: selected-file download progress for player UI.
//  Task #14: persist piece resume across launches.
//

import Foundation
import Observation
#if os(macOS)
import AppKit
import SwiftTorrent
#endif

@MainActor
@Observable
final class TorrentEngine {
    enum Phase: Equatable {
        case idle
        case starting
        case ready
        case unsupportedPlatform
        case adding
        case fetchingMetadata
        case loaded(ActiveTorrent)
        case error(String)
    }

    enum PlaybackPhase: Equatable {
        case idle
        case buffering
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastMagnetURI: String?
    private(set) var activeTorrent: ActiveTorrent?
    private(set) var selectedFileID: Int?
    private(set) var playbackPhase: PlaybackPhase = .idle
    private(set) var playbackURL: URL?
    private(set) var downloadProgress: Double = 0
    private(set) var downloadRateBytes: Double = 0
    private(set) var peersConnected: Int = 0
    private(set) var piecesCompleted: Int = 0
    private(set) var piecesTotal: Int = 0
    private(set) var usesExternalPlayer: Bool = false

    var selectedFile: TorrentFileItem? {
        guard let selectedFileID, let activeTorrent else { return nil }
        return activeTorrent.files.first { $0.id == selectedFileID && $0.isVideo }
    }

    /// On-disk URL for the selected video under Application Support downloads.
    var selectedFileURL: URL? {
        guard let selectedFile else { return nil }
        guard let downloads = try? Self.downloadsDirectory() else { return nil }
        return LocalHTTPStreamServer.diskURL(
            downloadsDirectory: downloads,
            relativePath: selectedFile.path
        )
    }

    /// AVPlayer only handles a few containers; MKV/AVI/etc. need an external player (e.g. VLC).
    static func isAVPlayerCompatible(path: String) -> Bool {
        switch (path as NSString).pathExtension.lowercased() {
        case "mp4", "m4v", "mov":
            true
        default:
            false
        }
    }

    #if os(macOS)
    private var session: Session?
    private var activeHandle: TorrentHandle?
    private var activeInfoHash: InfoHash?
    private var streamServer: LocalHTTPStreamServer?
    private var playbackGeneration: UInt64 = 0
    private var byteGateAdvanceTask: Task<Void, Never>?
    private var lastResumePersistAt: ContinuousClock.Instant?
    private var lastPersistedPiecesCompleted: Int = -1
    #endif

    private let metadataTimeoutSeconds: Int
    private let streamingLeadBytes: Int64
    private let streamingLeadTimeoutSeconds: Int
    private static let resumePersistInterval: Duration = .seconds(5)

    init(
        metadataTimeoutSeconds: Int = 10,
        streamingLeadBytes: Int64 = 2 * 1024 * 1024,
        streamingLeadTimeoutSeconds: Int = 120
    ) {
        self.metadataTimeoutSeconds = metadataTimeoutSeconds
        self.streamingLeadBytes = streamingLeadBytes
        self.streamingLeadTimeoutSeconds = streamingLeadTimeoutSeconds
    }

    var isLoadingTorrent: Bool {
        switch phase {
        case .adding, .fetchingMetadata:
            true
        default:
            false
        }
    }

    var isOperational: Bool {
        switch phase {
        case .ready, .loaded, .error:
            true
        default:
            false
        }
    }

    var statusLabel: String {
        switch phase {
        case .idle:
            "System Idle"
        case .starting:
            "Starting Session…"
        case .ready:
            "System Ready"
        case .unsupportedPlatform:
            "Torrent Engine: macOS Only (iOS Soon)"
        case .adding:
            "Accepting Magnet…"
        case .fetchingMetadata:
            "Fetching Metadata…"
        case let .loaded(torrent):
            "Loaded • \(torrent.files.count) Files"
        case let .error(message):
            "Error: \(message)"
        }
    }

    func selectFile(id: Int) {
        guard let activeTorrent,
              activeTorrent.videoFiles.contains(where: { $0.id == id })
        else { return }
        if selectedFileID != id {
            stopPlayback()
        }
        selectedFileID = id
        #if os(macOS)
        Task { await applySequentialPriorityForSelection() }
        #endif
    }

    /// Test helper: simulates a successful metadata load without the torrent session.
    func applyLoadedTorrentForTesting(_ torrent: ActiveTorrent) {
        activeTorrent = torrent
        selectedFileID = torrent.defaultSelectedFileID
        phase = .loaded(torrent)
    }

    func bootstrap() async {
        guard case .idle = phase else { return }
        phase = .starting

        #if os(macOS)
        do {
            let downloads = try Self.downloadsDirectory()
            let settings = SessionSettings(
                listenPort: 6881,
                dhtEnabled: true,
                dhtPort: 6882, // avoid clashing with listenPort
                savePath: downloads.path
            )
            let session = Session(settings: settings)
            do {
                try await session.startDHT()
                TPLog.engine("DHT started")
            } catch {
                TPLog.engine("DHT start failed (optional): \(error.localizedDescription)")
            }
            self.session = session
            phase = .ready
            TPLog.engine("Session ready savePath=\(downloads.path)")
        } catch {
            phase = .error(error.localizedDescription)
            TPLog.error("bootstrap failed: \(error.localizedDescription)")
        }
        #else
        phase = .unsupportedPlatform
        #endif
    }

    func addMagnet(_ uri: String) async throws {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .error(TorrentEngineError.emptyMagnet.localizedDescription)
            throw TorrentEngineError.emptyMagnet
        }

        #if os(macOS)
        guard let session else {
            phase = .error(TorrentEngineError.sessionNotReady.localizedDescription)
            throw TorrentEngineError.sessionNotReady
        }

        stopPlayback()

        let previousTorrent = activeTorrent
        let previousInfoHash = activeInfoHash
        let previousSelectedFileID = selectedFileID

        phase = .adding
        var pendingInfoHash: InfoHash?
        await Task.yield()
        TPLog.engine("addMagnet begin uriLen=\(trimmed.count)")

        do {
            let downloads = try Self.downloadsDirectory()
            var params = try AddTorrentParams.fromMagnet(trimmed, savePath: downloads.path)
            guard let infoHash = params.infoHash else {
                throw AddTorrentError.noInfoHash
            }
            pendingInfoHash = infoHash
            TPLog.engine("addMagnet infoHash=\(infoHash)")

            if let resume = Self.loadResumeData(infoHash: infoHash) {
                params.resumeData = resume
                TPLog.engine(
                    "loaded resume pieces=\(resume.completedPieces.popcount) downloaded=\(resume.downloaded)"
                )
            }

            // Persist active torrent before replacing the handle.
            if previousInfoHash != nil {
                await persistResumeIfNeeded(force: true)
            }

            let handle = try await session.addTorrent(params)
            activeHandle = handle

            phase = .fetchingMetadata
            await Task.yield()
            let info: TorrentInfo
            do {
                info = try await handle.waitForMetadata(timeout: metadataTimeoutSeconds)
                TPLog.engine("metadata OK name=\(info.name) files=\(info.files.count) pieces=\(info.pieceCount)")
            } catch is TorrentError {
                await session.removeTorrent(infoHash)
                pendingInfoHash = nil
                activeHandle = nil
                activeInfoHash = previousInfoHash
                failOrRestore(
                    previousTorrent: previousTorrent,
                    previousSelectedFileID: previousSelectedFileID,
                    message: TorrentEngineError.metadataTimeout.localizedDescription
                )
                throw TorrentEngineError.metadataTimeout
            }

            if let previousInfoHash, previousInfoHash != infoHash {
                await session.removeTorrent(previousInfoHash)
            }

            let hash = infoHash.description
            let torrent = ActiveTorrent.from(info: info, infoHash: hash)
            activeTorrent = torrent
            selectedFileID = torrent.defaultSelectedFileID
            activeInfoHash = infoHash
            lastMagnetURI = trimmed
            pendingInfoHash = nil
            lastPersistedPiecesCompleted = -1
            lastResumePersistAt = nil
            phase = .loaded(torrent)
            await applySequentialPriorityForSelection()
            await persistResumeIfNeeded(force: true)
        } catch let error as TorrentEngineError {
            if case .metadataTimeout = error {
                throw error
            }
            if let pendingInfoHash {
                await session.removeTorrent(pendingInfoHash)
            }
            activeHandle = nil
            activeInfoHash = previousInfoHash
            failOrRestore(
                previousTorrent: previousTorrent,
                previousSelectedFileID: previousSelectedFileID,
                message: error.localizedDescription
            )
            throw error
        } catch {
            if let pendingInfoHash {
                await session.removeTorrent(pendingInfoHash)
            }
            activeHandle = nil
            activeInfoHash = previousInfoHash
            failOrRestore(
                previousTorrent: previousTorrent,
                previousSelectedFileID: previousSelectedFileID,
                message: error.localizedDescription
            )
            throw error
        }
        #else
        phase = .error(TorrentEngineError.unsupportedPlatform.localizedDescription)
        throw TorrentEngineError.unsupportedPlatform
        #endif
    }

    /// Waits for leading sequential bytes, then starts a loopback HTTP server for AVPlayer.
    func preparePlayback() async {
        #if os(macOS)
        stopPlayback()
        let generation = playbackGeneration

        guard let file = selectedFile, let handle = activeHandle else {
            playbackPhase = .failed(TorrentEngineError.noSelectedFile.localizedDescription)
            return
        }
        guard let diskURL = selectedFileURL else {
            playbackPhase = .failed(TorrentEngineError.noSelectedFile.localizedDescription)
            return
        }

        playbackPhase = .buffering
        let fileIndex = file.id
        let leadBytes = min(streamingLeadBytes, max(file.size, 1))
        usesExternalPlayer = !Self.isAVPlayerCompatible(path: file.path)
        TPLog.playback(
            "preparePlayback file=\(file.path) index=\(fileIndex) leadBytes=\(leadBytes) external=\(usesExternalPlayer) disk=\(diskURL.path)"
        )

        do {
            await applySequentialPriorityForSelection()
            try await waitForLeadingBytesPolling(
                handle: handle,
                fileIndex: fileIndex,
                bytes: leadBytes,
                generation: generation
            )
            guard generation == playbackGeneration else {
                TPLog.playback("preparePlayback aborted (stale generation after lead wait)")
                return
            }

            // HTTP handlers must not await TorrentHandle — under peer load that stalls
            // every VLC/browser request. Lead bytes are already on disk; a background
            // task advances the gate as more contiguous bytes arrive.
            let gate = StreamingByteGate()
            gate.markReady(through: leadBytes)
            let waiter: LocalHTTPStreamServer.ByteWaiter = { offset, length in
                gate.isReady(offset: offset, length: length)
            }

            let server = LocalHTTPStreamServer(
                fileURL: diskURL,
                fileSize: file.size,
                contentType: LocalHTTPStreamServer.contentType(forPath: file.path),
                waitForBytes: waiter
            )
            try await server.start()
            guard generation == playbackGeneration else {
                server.stop()
                TPLog.playback("preparePlayback aborted (stale generation after server start)")
                return
            }
            guard let url = server.streamURL else {
                server.stop()
                throw TorrentEngineError.playbackServerFailed("No port bound")
            }
            streamServer = server
            playbackURL = url
            playbackPhase = .ready
            startByteGateAdvance(
                gate: gate,
                handle: handle,
                fileIndex: fileIndex,
                fileSize: file.size,
                from: leadBytes,
                generation: generation
            )
            TPLog.playback("stream ready url=\(url.absoluteString) lead=\(leadBytes)")

            if usesExternalPlayer {
                openInExternalPlayer(url)
            }
        } catch is TorrentError {
            guard generation == playbackGeneration else { return }
            TPLog.error("playback buffer timeout")
            playbackPhase = .failed(TorrentEngineError.playbackBufferTimeout.localizedDescription)
        } catch let error as TorrentEngineError {
            guard generation == playbackGeneration else { return }
            TPLog.error("playback failed: \(error.localizedDescription)")
            playbackPhase = .failed(error.localizedDescription)
        } catch {
            guard generation == playbackGeneration else { return }
            TPLog.error("playback server failed: \(error.localizedDescription)")
            playbackPhase = .failed(
                TorrentEngineError.playbackServerFailed(error.localizedDescription).localizedDescription
            )
        }
        #else
        playbackPhase = .failed(TorrentEngineError.unsupportedPlatform.localizedDescription)
        #endif
    }

    func stopPlayback() {
        #if os(macOS)
        playbackGeneration += 1
        byteGateAdvanceTask?.cancel()
        byteGateAdvanceTask = nil
        streamServer?.stop()
        streamServer = nil
        #endif
        playbackURL = nil
        playbackPhase = .idle
        usesExternalPlayer = false
    }

    func refreshDownloadStatus() async {
        #if os(macOS)
        guard let handle = activeHandle else {
            downloadProgress = 0
            downloadRateBytes = 0
            peersConnected = 0
            piecesCompleted = 0
            piecesTotal = 0
            return
        }
        let status = await handle.status()
        downloadRateBytes = status.downloadRate
        peersConnected = status.numPeers
        if let selectedFileID, let counts = await handle.filePieceCounts(fileIndex: selectedFileID) {
            downloadProgress = counts.total > 0
                ? Double(counts.completed) / Double(counts.total)
                : 0
            piecesCompleted = counts.completed
            piecesTotal = counts.total
        } else {
            downloadProgress = status.progress
            piecesCompleted = status.piecesCompleted
            piecesTotal = status.piecesTotal
        }
        if playbackPhase == .buffering {
            TPLog.playback(
                "status peers=\(status.numPeers) pieces=\(piecesCompleted)/\(piecesTotal) progress=\(String(format: "%.4f", downloadProgress)) rate=\(Int(status.downloadRate))B/s"
            )
        }
        await persistResumeIfNeeded(force: false)
        #endif
    }

    /// Save resume data for the active torrent (throttled unless `force`).
    func persistResumeIfNeeded(force: Bool = false) async {
        #if os(macOS)
        guard let handle = activeHandle, let infoHash = activeInfoHash else { return }

        let now = ContinuousClock.now
        if !force {
            if let last = lastResumePersistAt, now - last < Self.resumePersistInterval {
                return
            }
            if piecesCompleted == lastPersistedPiecesCompleted {
                return
            }
        }

        guard let resume = await handle.generateResumeData() else { return }
        do {
            try Self.writeResumeData(resume, infoHash: infoHash)
            lastResumePersistAt = now
            lastPersistedPiecesCompleted = piecesCompleted
            TPLog.engine("saved resume pieces=\(resume.completedPieces.popcount)")
        } catch {
            TPLog.error("resume save failed: \(error.localizedDescription)")
        }
        #endif
    }

    #if os(macOS)
    private func waitForLeadingBytesPolling(
        handle: TorrentHandle,
        fileIndex: Int,
        bytes: Int64,
        generation: UInt64
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(streamingLeadTimeoutSeconds)
        while ContinuousClock.now < deadline {
            guard generation == playbackGeneration else { return }
            await refreshDownloadStatus()
            do {
                try await handle.waitForLeadingBytes(
                    fileIndex: fileIndex,
                    bytes: bytes,
                    timeout: 2
                )
                await refreshDownloadStatus()
                return
            } catch is TorrentError {
                // keep polling until overall timeout
            }
        }
        throw TorrentError.timeout
    }

    /// Surfaces the failure while keeping a previously loaded torrent (if any)
    /// so Files can still show it; Load UI reads `phase == .error`.
    private func failOrRestore(
        previousTorrent: ActiveTorrent?,
        previousSelectedFileID: Int?,
        message: String
    ) {
        if let previousTorrent {
            activeTorrent = previousTorrent
            selectedFileID = previousSelectedFileID
        } else {
            activeTorrent = nil
            selectedFileID = nil
        }
        phase = .error(message)
    }

    private func applySequentialPriorityForSelection() async {
        guard let handle = activeHandle, let selectedFileID else { return }
        await handle.prioritizeFile(selectedFileID, sequential: true)
    }

    /// Extends `gate` as sequential torrent bytes become available (off the HTTP path).
    private func startByteGateAdvance(
        gate: StreamingByteGate,
        handle: TorrentHandle,
        fileIndex: Int,
        fileSize: Int64,
        from startOffset: Int64,
        generation: UInt64
    ) {
        byteGateAdvanceTask?.cancel()
        byteGateAdvanceTask = Task.detached { [weak self] in
            let step: Int64 = 256 * 1024
            var cursor = startOffset
            while !Task.isCancelled, cursor < fileSize {
                guard let self, await self.isPlaybackGeneration(generation) else { return }
                let length = min(step, fileSize - cursor)
                do {
                    try await handle.waitForFileBytes(
                        fileIndex: fileIndex,
                        fileOffset: cursor,
                        length: length,
                        timeout: 2
                    )
                    cursor += length
                    gate.markReady(through: cursor)
                } catch {
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            TPLog.playback("byte gate reached end offset=\(cursor)")
        }
    }

    private func isPlaybackGeneration(_ generation: UInt64) -> Bool {
        generation == playbackGeneration
    }

    /// MKV/AVI are opened in VLC. `NSWorkspace.shared.open(url)` uses the default
    /// http(s) handler (Safari/Chrome) and will not play Matroska.
    private func openInExternalPlayer(_ url: URL) {
        let candidates = [
            URL(fileURLWithPath: "/Applications/VLC.app"),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications/VLC.app"),
        ]
        guard let vlc = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            TPLog.error("VLC.app not found — install VLC or open \(url.absoluteString) manually")
            playbackPhase = .failed(
                "VLC not found. Install VLC from videolan.org, then try Stream Now again."
            )
            return
        }
        TPLog.playback("opening VLC at \(vlc.path) url=\(url.absoluteString)")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: vlc,
            configuration: configuration
        ) { _, error in
            if let error {
                TPLog.error("VLC open failed: \(error.localizedDescription)")
            }
        }
    }
    #endif

    static func downloadsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("TorrentPlayer/Downloads", isDirectory: true)

        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    #if os(macOS)
    nonisolated static func resumeDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("TorrentPlayer/Resume", isDirectory: true)

        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    nonisolated static func resumeFileURL(infoHash: InfoHash, in directory: URL) -> URL {
        directory.appendingPathComponent("\(infoHash.description).dat", isDirectory: false)
    }

    nonisolated static func loadResumeData(infoHash: InfoHash, directory: URL? = nil) -> ResumeData? {
        do {
            let dir = try directory ?? resumeDirectory()
            let url = resumeFileURL(infoHash: infoHash, in: dir)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            let resume = try ResumeData.decode(from: data)
            guard resume.infoHash == infoHash else {
                TPLog.engine("resume hash mismatch for \(infoHash), ignoring")
                return nil
            }
            return resume
        } catch {
            TPLog.error("resume load failed: \(error.localizedDescription)")
            return nil
        }
    }

    nonisolated static func writeResumeData(_ resume: ResumeData, infoHash: InfoHash, directory: URL? = nil) throws {
        let dir = try directory ?? resumeDirectory()
        let url = resumeFileURL(infoHash: infoHash, in: dir)
        try resume.encode().write(to: url, options: .atomic)
    }
    #endif
}
