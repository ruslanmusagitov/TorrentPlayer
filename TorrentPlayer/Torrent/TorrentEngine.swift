//
//  TorrentEngine.swift
//  TorrentPlayer
//
//  Task #3: torrent session; Task #11: iOS (SwiftTorrent SPM).
//  Task #4: metadata fetch and file list.
//  Task #5: video file selection.
//  Task #6: sequential download of selected file.
//  Task #7: local HTTP stream bridge → AVPlayer.
//  Task #8: selected-file download progress for player UI.
//  Task #14: persist piece resume across launches.
//

import Foundation
import Observation
#if os(macOS) || os(iOS)
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

    /// Discrete app-layer bootstrap steps for splash (not torrent lifecycle).
    enum BootStep: Equatable {
        case idle
        case preparingStorage
        case startingSession
        case bindingPeerPort
        case bootstrappingDHT
        case ready
        case failed(String)

        var isTerminal: Bool {
            switch self {
            case .ready, .failed:
                true
            default:
                false
            }
        }

        var statusLine: String {
            switch self {
            case .idle:
                "> WAITING..."
            case .preparingStorage:
                "> PREPARING_STORAGE..."
            case .startingSession:
                "> STARTING_SESSION..."
            case .bindingPeerPort:
                "> BINDING_PEER_PORT..."
            case .bootstrappingDHT:
                "> BOOTSTRAPPING_DHT..."
            case .ready:
                "> ENGINE_READY_STABLE"
            case .failed:
                "> BOOT_FAILED"
            }
        }

        var secondaryLine: String {
            switch self {
            case .idle:
                "AWAITING_BOOTSTRAP"
            case .preparingStorage:
                "CREATING_DOWNLOADS_DIRECTORY"
            case .startingSession:
                "ALLOCATING_TORRENT_SESSION"
            case .bindingPeerPort:
                "OPENING_PEER_LISTEN_PORT"
            case .bootstrappingDHT:
                "CONTACTING_DHT_BOOTSTRAP_NODES"
            case .ready:
                "SESSION_OPERATIONAL"
            case let .failed(message):
                message.uppercased()
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var bootStep: BootStep = .idle
    private(set) var bootProgress: Double = 0
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
    private(set) var usesEmbeddedVLC: Bool = false
    /// Whether completed pieces are uploaded to peers (Settings toggle, default off).
    private(set) var seedingEnabled: Bool = AppPreferences.seedingEnabled

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

    /// AVPlayer only handles a few containers; MKV/AVI/etc. need embedded SwiftVLC.
    static func isAVPlayerCompatible(path: String) -> Bool {
        switch (path as NSString).pathExtension.lowercased() {
        case "mp4", "m4v", "mov":
            true
        default:
            false
        }
    }

    #if os(macOS) || os(iOS)
    private var session: Session?
    private var activeHandle: TorrentHandle?
    private var activeInfoHash: InfoHash?
    private var streamServer: LocalHTTPStreamServer?
    private var playbackGeneration: UInt64 = 0
    private var byteGateAdvanceTask: Task<Void, Never>?
    private var resumePersistTask: Task<Void, Never>?
    private var lastResumePersistAt: ContinuousClock.Instant?
    private var lastPersistedPiecesCompleted: Int = -1
    /// Cleared by Settings → Clear Resume until the next torrent load restarts persistence.
    private var resumePersistenceEnabled = true
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
            "Torrent Engine Unavailable"
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
        #if os(macOS) || os(iOS)
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

        #if os(macOS) || os(iOS)
        do {
            bootStep = .preparingStorage
            bootProgress = 0.15
            let downloads = try Self.downloadsDirectory()

            bootStep = .startingSession
            bootProgress = 0.35
            let settings = SessionSettings(
                listenPort: 6881,
                dhtEnabled: true,
                dhtPort: 6882, // avoid clashing with listenPort
                savePath: downloads.path,
                seedingEnabled: AppPreferences.seedingEnabled
            )
            let session = Session(settings: settings)

            bootStep = .bindingPeerPort
            bootProgress = 0.55
            do {
                try await session.startListening()
                TPLog.engine("Listening for peers on port \(settings.listenPort)")
            } catch {
                TPLog.engine("Listen failed (optional): \(error.localizedDescription)")
            }

            bootStep = .bootstrappingDHT
            bootProgress = 0.85
            do {
                try await session.startDHT()
                TPLog.engine("DHT started")
            } catch {
                TPLog.engine("DHT start failed (optional): \(error.localizedDescription)")
            }

            self.session = session
            bootStep = .ready
            bootProgress = 1
            phase = .ready
            TPLog.engine("Session ready savePath=\(downloads.path)")
        } catch {
            let message = error.localizedDescription
            bootStep = .failed(message)
            bootProgress = 1
            phase = .error(message)
            TPLog.error("bootstrap failed: \(message)")
        }
        #else
        bootStep = .failed("Unsupported platform")
        bootProgress = 1
        phase = .unsupportedPlatform
        #endif
    }

    func addMagnet(_ uri: String) async throws {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .error(TorrentEngineError.emptyMagnet.localizedDescription)
            throw TorrentEngineError.emptyMagnet
        }

        #if os(macOS) || os(iOS)
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
            stopResumePersistLoop()

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
            resumePersistenceEnabled = true
            await persistResumeIfNeeded(force: true)
            startResumePersistLoop()
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
        #if os(macOS) || os(iOS)
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
        usesEmbeddedVLC = !Self.isAVPlayerCompatible(path: file.path)
        TPLog.playback(
            "preparePlayback file=\(file.path) index=\(fileIndex) leadBytes=\(leadBytes) embeddedVLC=\(usesEmbeddedVLC) disk=\(diskURL.path)"
        )

        do {
            await applySequentialPriorityForSelection()
            try await waitForFileBytesPolling(
                handle: handle,
                fileIndex: fileIndex,
                fileOffset: 0,
                bytes: leadBytes,
                generation: generation
            )
            guard generation == playbackGeneration else {
                TPLog.playback("preparePlayback aborted (stale generation after lead wait)")
                return
            }

            // MKV/AVI (SwiftVLC) probe cues near EOF immediately. Fetch a trailing
            // window before advertising the stream, then resume sequential download.
            var tailOffset: Int64 = 0
            var tailBytes: Int64 = 0
            if usesEmbeddedVLC, file.size > leadBytes {
                tailBytes = min(streamingLeadBytes, file.size - leadBytes)
                tailOffset = file.size - tailBytes
                TPLog.playback("preparePlayback fetching VLC tail offset=\(tailOffset) bytes=\(tailBytes)")
                await handle.prioritizeFileBytes(
                    fileIndex: fileIndex,
                    fileOffset: tailOffset,
                    length: tailBytes,
                    sequential: true
                )
                try await waitForFileBytesPolling(
                    handle: handle,
                    fileIndex: fileIndex,
                    fileOffset: tailOffset,
                    bytes: tailBytes,
                    generation: generation
                )
                guard generation == playbackGeneration else {
                    TPLog.playback("preparePlayback aborted (stale generation after tail wait)")
                    return
                }
                await applySequentialPriorityForSelection()
            }

            // HTTP handlers must not await TorrentHandle — under peer load that stalls
            // every player/browser request. Lead (+ optional tail) bytes are already on
            // disk; a background task advances the gate as more contiguous bytes arrive.
            let gate = StreamingByteGate()
            gate.markReady(through: leadBytes)
            if tailBytes > 0 {
                gate.markReady(range: tailOffset..<(tailOffset + tailBytes))
            }
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
            TPLog.playback(
                "stream ready url=\(url.absoluteString) lead=\(leadBytes) tail=\(tailBytes)"
            )
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
        #if os(macOS) || os(iOS)
        playbackGeneration += 1
        byteGateAdvanceTask?.cancel()
        byteGateAdvanceTask = nil
        streamServer?.stop()
        streamServer = nil
        #endif
        playbackURL = nil
        playbackPhase = .idle
        usesEmbeddedVLC = false
    }

    func refreshDownloadStatus() async {
        #if os(macOS) || os(iOS)
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
        #if os(macOS) || os(iOS)
        guard resumePersistenceEnabled else { return }
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

    #if os(macOS) || os(iOS)
    private func startResumePersistLoop() {
        stopResumePersistLoop()
        resumePersistenceEnabled = true
        resumePersistTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.resumePersistInterval)
                guard !Task.isCancelled else { return }
                await self?.persistResumeIfNeeded(force: true)
            }
        }
    }

    private func stopResumePersistLoop() {
        resumePersistTask?.cancel()
        resumePersistTask = nil
    }
    #endif

    #if os(macOS) || os(iOS)
    private func waitForFileBytesPolling(
        handle: TorrentHandle,
        fileIndex: Int,
        fileOffset: Int64,
        bytes: Int64,
        generation: UInt64
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(streamingLeadTimeoutSeconds)
        while ContinuousClock.now < deadline {
            guard generation == playbackGeneration else { return }
            await refreshDownloadStatus()
            do {
                try await handle.waitForFileBytes(
                    fileIndex: fileIndex,
                    fileOffset: fileOffset,
                    length: bytes,
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

    static func logsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("TorrentPlayer/Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func downloadsDiskUsageBytes() -> Int64 {
        guard let dir = try? downloadsDirectory() else { return 0 }
        return directoryByteSize(at: dir)
    }

    /// Stops playback, removes the active torrent from the session, and deletes Downloads contents.
    /// Also wipes Resume/ so the next magnet load cannot restore phantom completed pieces.
    func clearDownloads() async throws {
        #if os(macOS) || os(iOS)
        stopResumePersistLoop()
        resumePersistenceEnabled = false
        stopPlayback()
        if let session, let infoHash = activeInfoHash {
            await session.removeTorrent(infoHash)
        }
        activeHandle = nil
        activeInfoHash = nil
        #else
        stopPlayback()
        #endif

        activeTorrent = nil
        selectedFileID = nil
        lastMagnetURI = nil
        downloadProgress = 0
        downloadRateBytes = 0
        peersConnected = 0
        piecesCompleted = 0
        piecesTotal = 0
        #if os(macOS) || os(iOS)
        if session != nil {
            phase = .ready
        }
        #endif

        let dir = try Self.downloadsDirectory()
        try Self.removeContents(of: dir)
        #if os(macOS) || os(iOS)
        try wipeResumeDirectory()
        #endif
        TPLog.engine("cleared downloads at \(dir.path)")
    }

    /// Persist preference and apply immediately to the live session / active torrent.
    func setSeedingEnabled(_ enabled: Bool) async {
        AppPreferences.seedingEnabled = enabled
        seedingEnabled = enabled
        TPLog.engine("seedingEnabled=\(enabled)")
        #if os(macOS) || os(iOS)
        await session?.setSeedingEnabled(enabled)
        #endif
    }

    /// Deletes all resume `.dat` files under Application Support/TorrentPlayer/Resume.
    /// Stops persistence so an active torrent cannot rewrite resume within ~5s.
    func clearResumeData() throws {
        #if os(macOS) || os(iOS)
        stopResumePersistLoop()
        resumePersistenceEnabled = false
        try wipeResumeDirectory()
        TPLog.engine("cleared resume data")
        #endif
    }

    #if os(macOS) || os(iOS)
    private func wipeResumeDirectory() throws {
        let dir = try Self.resumeDirectory()
        try Self.removeContents(of: dir)
        lastResumePersistAt = nil
        lastPersistedPiecesCompleted = -1
    }
    #endif

    private static func removeContents(of directory: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        let items = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for item in items {
            try fm.removeItem(at: item)
        }
    }

    private static func directoryByteSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            total += Int64(size)
        }
        return total
    }

    #if os(macOS) || os(iOS)
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
