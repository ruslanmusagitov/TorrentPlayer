import Foundation
import NIOCore
import NIOPosix

/// Errors thrown by TorrentHandle wait methods.
public enum TorrentError: Error {
    case timeout
}

/// Per-torrent controller tying peers, pieces, and disk together.
public actor TorrentHandle {
    public let infoHash: InfoHash
    private var info: TorrentInfo?
    private let magnetLink: MagnetLink?
    private let savePath: String
    private let peerID: Data
    private let group: EventLoopGroup

    private var peerManager: PeerManager
    private var pieceManager: PieceManager?
    private var piecePicker: PiecePicker?
    private var diskIO: DiskIO?
    private var trackerManager: TrackerManager?
    private var state: TorrentState = .paused
    private var totalDownloaded: Int64 = 0
    private var totalUploaded: Int64 = 0
    private var lastDownloadRateSample: Int64 = 0
    private var lastUploadRateSample: Int64 = 0
    private var downloadRate: Double = 0
    private var uploadRate: Double = 0
    /// Empty monitor ticks before clearing `downloadRate` (piece completions are bursty).
    private var downloadRateZeroTicks: Int = 0
    private var reannounceTask: Task<Void, Never>?
    private var downloadMonitorTask: Task<Void, Never>?
    private var metadataExchange: MetadataExchange?
    private var metadataContinuations: [UInt64: CheckedContinuation<TorrentInfo, Error>] = [:]
    private var completionContinuations: [UInt64: CheckedContinuation<Void, Error>] = [:]
    private var nextWaitID: UInt64 = 0

    public init(params: AddTorrentParams, settings: SessionSettings, group: EventLoopGroup) {
        let hash = params.infoHash!
        self.infoHash = hash
        self.info = params.torrentInfo
        self.magnetLink = params.magnetLink
        self.savePath = params.savePath ?? settings.savePath
        self.peerID = generatePeerID()
        self.group = group
        self.peerManager = PeerManager(
            infoHash: hash.bytes, peerID: peerID, group: group,
            maxConnections: settings.maxConnectionsPerTorrent
        )

        if let magnet = params.magnetLink, !magnet.trackers.isEmpty {
            let tiers = magnet.trackers.map { [$0] }
            self.trackerManager = TrackerManager(tiers: tiers, group: group)
        }
    }

    private func setupDownloadComponents(info: TorrentInfo) async {
        self.info = info
        let pm = PieceManager(info: info)
        var pp = PiecePicker(pieceCount: info.pieceCount)
        // Hold piece requests until prioritizeFile sets an interested range.
        pp.setSequential(range: 0..<0)
        let fs = FileStorage(info: info)
        let dio = DiskIO(basePath: savePath, fileStorage: fs)
        self.pieceManager = pm
        self.piecePicker = pp
        self.diskIO = dio

        if self.trackerManager == nil {
            self.trackerManager = TrackerManager(info: info, group: group)
        }

        await peerManager.configure(
            pieceManager: pm, piecePicker: pp, diskIO: dio,
            pieceCount: info.pieceCount
        )
        await peerManager.setOnPieceCompleted { [weak self] index in
            Task { await self?.notePieceDownloaded(index: index) }
        }
    }

    private func notePieceDownloaded(index: Int) async {
        guard let pm = pieceManager else { return }
        totalDownloaded += Int64(await pm.expectedPieceSize(index))
        lastDownloadRateSample += Int64(await pm.expectedPieceSize(index))
    }

    /// Complete initialization for .torrent-file init path (must be called after init).
    internal func finishInitialization() async {
        if let info = self.info {
            await setupDownloadComponents(info: info)
        }
    }

    /// Start downloading.
    public func start() async throws {
        guard state == .paused || state == .stopped else { return }

        if info != nil {
            state = .downloading
            // Allocate files on disk
            try? await diskIO?.allocateFiles()
            startDownloadMonitor()
        } else if magnetLink != nil {
            state = .downloadingMetadata
            // Set up metadata exchange
            let metaEx = MetadataExchange(infoHash: infoHash)
            self.metadataExchange = metaEx
            await peerManager.configureMagnet(metadataExchange: metaEx)
            let weakSelf = self
            await peerManager.setOnMetadataReceived { info in
                Task { await weakSelf.onMetadataReceived(info: info) }
            }
        } else {
            state = .downloading
        }

        // Announce to trackers
        if let trackerMgr = trackerManager {
            // Magnet announce before metadata: left must be > 0 or trackers treat us as a seeder.
            let left = info?.totalSize ?? (1 << 30)
            let params = AnnounceParams(
                infoHash: infoHash, peerID: peerID, port: 6881,
                left: left - totalDownloaded, event: "started"
            )
            await announceToAllTrackers(trackerMgr: trackerMgr, params: params)
            startReannounceLoop(trackerMgr: trackerMgr)
        }
    }

    private func onMetadataReceived(info: TorrentInfo) async {
        // Duplicate ut_metadata completions must not reset the picker / drop peers.
        if self.info != nil, pieceManager != nil {
            TorrentLog.session("onMetadataReceived ignored (already set up)")
            return
        }

        TorrentLog.session(
            "onMetadataReceived name=\(info.name) pieces=\(info.pieceCount) pieceLength=\(info.pieceLength) size=\(info.totalSize)"
        )
        await setupDownloadComponents(info: info)
        state = .downloading
        // Stop magnet metadata exchange — further extended messages are noise.
        metadataExchange = nil
        await peerManager.clearMetadataExchange()
        try? await diskIO?.allocateFiles()
        startDownloadMonitor()

        // Metadata-era peers used pieceCount=0/1 and are not useful for piece download.
        TorrentLog.session("disconnecting metadata-era peers")
        await peerManager.disconnectAll()

        // Resume waiters so the app can prioritizeFile before new peers arrive.
        let conts = metadataContinuations
        metadataContinuations.removeAll()
        for (_, cont) in conts {
            cont.resume(returning: info)
        }

        // Re-announce with the real size so we get download peers.
        if let trackerMgr = trackerManager {
            let params = AnnounceParams(
                infoHash: infoHash, peerID: peerID, port: 6881,
                left: info.totalSize, event: "started"
            )
            TorrentLog.session("re-announce after metadata left=\(info.totalSize)")
            await announceToAllTrackers(trackerMgr: trackerMgr, params: params)
        }
    }

    private static let downloadMonitorIntervalSeconds: Double = 2
    /// Keep last non-zero rate across this many empty 2s windows (~6s) so UI doesn't flicker.
    private static let downloadRateHoldZeroTicks = 3

    private func startDownloadMonitor() {
        downloadMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.downloadMonitorIntervalSeconds))
                guard let self, !Task.isCancelled else { break }
                let complete = await self.checkCompletion()
                if complete {
                    await self.transitionToSeeding()
                    break
                }
                await self.peerManager.checkTimeouts()
                // Rough rate from bytes completed in this monitor tick.
                let sample = await self.lastDownloadRateSample
                await self.updateDownloadRate(sampleBytes: sample)
                await self.resetDownloadRateSample()
            }
        }
    }

    private func updateDownloadRate(sampleBytes: Int64) {
        let instant = Double(sampleBytes) / Self.downloadMonitorIntervalSeconds
        if instant > 0 {
            // Blend so a single fat piece doesn't spike the displayed rate alone.
            downloadRate = downloadRate > 0 ? (downloadRate * 0.4 + instant * 0.6) : instant
            downloadRateZeroTicks = 0
        } else {
            downloadRateZeroTicks += 1
            if downloadRateZeroTicks >= Self.downloadRateHoldZeroTicks {
                downloadRate = 0
            }
            // else keep previous downloadRate — empty ticks are normal between pieces
        }
    }

    private func resetDownloadRateSample() {
        lastDownloadRateSample = 0
    }

    private func checkCompletion() async -> Bool {
        guard let pm = pieceManager else { return false }
        return await pm.isComplete()
    }

    private func transitionToSeeding() {
        state = .seeding
        downloadMonitorTask?.cancel()

        // Resume all waiting completion continuations
        let conts = completionContinuations
        completionContinuations.removeAll()
        for (_, cont) in conts {
            cont.resume()
        }
    }

    /// Announce to all tracker tiers concurrently.
    private func announceToAllTrackers(trackerMgr: TrackerManager, params: AnnounceParams) async {
        if let response = try? await trackerMgr.announce(params: params) {
            TorrentLog.session("announce OK peers=\(response.peers.count) interval=\(response.interval)")
            for (address, port) in response.peers {
                await peerManager.addPeer(address: address, port: port)
            }
        } else {
            TorrentLog.error("Session", "announce failed or empty response")
        }
    }

    /// Periodically re-announce to trackers.
    private func startReannounceLoop(trackerMgr: TrackerManager) {
        reannounceTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = await trackerMgr.getInterval()
                try? await Task.sleep(for: .seconds(max(interval, 60)))
                guard let self, !Task.isCancelled else { break }

                let left = await self.getRemainingBytes()
                let infoHash = await self.infoHash
                let peerID = await self.peerID
                let uploaded = await self.totalUploaded
                let downloaded = await self.totalDownloaded
                let params = AnnounceParams(
                    infoHash: infoHash, peerID: peerID, port: 6881,
                    uploaded: uploaded, downloaded: downloaded,
                    left: left
                )
                if let response = try? await trackerMgr.announce(params: params) {
                    for (address, port) in response.peers {
                        await self.peerManager.addPeer(address: address, port: port)
                    }
                }
            }
        }
    }

    private func getRemainingBytes() -> Int64 {
        (info?.totalSize ?? 0) - totalDownloaded
    }

    /// Pause the torrent.
    public func pause() {
        state = .paused
        reannounceTask?.cancel()
        downloadMonitorTask?.cancel()
    }

    /// Resume the torrent.
    public func resume() async throws {
        try await start()
    }

    /// Get current status snapshot.
    public func status() async -> TorrentStatus {
        let progress = await pieceManager?.progress() ?? 0
        let completed = await pieceManager?.getCompleted()
        let name: String
        if let info = info {
            name = info.name
        } else if let dn = magnetLink?.displayName {
            name = dn
        } else {
            name = "Unknown"
        }
        return TorrentStatus(
            infoHash: infoHash,
            name: name,
            state: state,
            progress: progress,
            downloadRate: downloadRate,
            uploadRate: uploadRate,
            totalDownloaded: totalDownloaded,
            totalUploaded: totalUploaded,
            totalSize: info?.totalSize ?? 0,
            numPeers: await peerManager.connectedCount,
            numSeeds: 0,
            piecesCompleted: completed?.popcount ?? 0,
            piecesTotal: info?.pieceCount ?? 0
        )
    }

    /// Fraction of pieces covering `fileIndex` that are complete (0…1).
    public func fileProgress(fileIndex: Int) async -> Double {
        guard let counts = await filePieceCounts(fileIndex: fileIndex), counts.total > 0 else {
            return 0
        }
        return Double(counts.completed) / Double(counts.total)
    }

    /// Completed / total piece counts for the range covering `fileIndex`.
    public func filePieceCounts(fileIndex: Int) async -> (completed: Int, total: Int)? {
        guard let info, let pm = pieceManager else { return nil }
        let storage = FileStorage(info: info)
        guard let range = storage.pieceRange(forFileIndex: fileIndex), !range.isEmpty else {
            return nil
        }
        let bitfield = await pm.getCompleted()
        var completed = 0
        for index in range where bitfield.get(index) {
            completed += 1
        }
        return (completed, range.count)
    }

    /// Download only pieces belonging to `fileIndex`, in start→end order when `sequential` is true.
    /// No-op if metadata is missing or the file index is invalid.
    public func prioritizeFile(_ fileIndex: Int, sequential: Bool = true) async {
        guard let info else {
            TorrentLog.session("prioritizeFile(\(fileIndex)) skipped — no metadata")
            return
        }
        let storage = FileStorage(info: info)
        guard let range = storage.pieceRange(forFileIndex: fileIndex) else {
            TorrentLog.session("prioritizeFile(\(fileIndex)) skipped — invalid file index")
            return
        }
        let mode: PiecePickMode = sequential ? .sequential : .rarestFirst
        TorrentLog.session(
            "prioritizeFile(\(fileIndex)) range=\(range.lowerBound)..<\(range.upperBound) mode=\(mode) piecesTotal=\(info.pieceCount)"
        )

        await peerManager.applyPiecePriority(range: range, mode: mode)
        if var local = piecePicker {
            local.setPriority(range: range, mode: mode)
            piecePicker = local
        }
    }

    /// Returns the file entries for this torrent, or nil if metadata is not yet available.
    public func getFiles() -> [TorrentInfo.FileEntry]? {
        info?.files
    }

    /// Returns a single file entry, or nil if metadata is missing / index is out of range.
    public func fileEntry(at index: Int) -> TorrentInfo.FileEntry? {
        guard let files = info?.files, index >= 0, index < files.count else { return nil }
        return files[index]
    }

    /// Absolute on-disk path for `fileIndex` under this handle's save path.
    public func filePath(forFileIndex index: Int) -> String? {
        guard let entry = fileEntry(at: index) else { return nil }
        return (savePath as NSString).appendingPathComponent(entry.path)
    }

    /// Whether every piece in `range` is complete.
    public func hasContiguousPieces(_ range: Range<Int>) async -> Bool {
        guard let pm = pieceManager else { return false }
        for index in range {
            if !(await pm.hasPiece(index)) { return false }
        }
        return true
    }

    /// Waits until the leading `bytes` of `fileIndex` are on disk (contiguous pieces), or throws `TorrentError.timeout`.
    public func waitForLeadingBytes(fileIndex: Int, bytes: Int64, timeout seconds: Int) async throws {
        try await waitForFileBytes(fileIndex: fileIndex, fileOffset: 0, length: bytes, timeout: seconds)
    }

    /// Waits until `[fileOffset, fileOffset + length)` within `fileIndex` is on disk, or throws `TorrentError.timeout`.
    public func waitForFileBytes(
        fileIndex: Int,
        fileOffset: Int64,
        length: Int64,
        timeout seconds: Int
    ) async throws {
        guard let info else { throw TorrentError.timeout }
        let storage = FileStorage(info: info)
        guard let range = storage.pieceRange(
            forFileIndex: fileIndex,
            fileOffset: fileOffset,
            length: length
        ) else {
            throw TorrentError.timeout
        }

        if await hasContiguousPieces(range) { return }

        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(200))
            if await hasContiguousPieces(range) { return }
        }
        throw TorrentError.timeout
    }

    /// Generate resume data for saving state.
    public func generateResumeData() async -> ResumeData? {
        guard let completed = await pieceManager?.getCompleted() else { return nil }
        return ResumeData(
            infoHash: infoHash, completedPieces: completed,
            uploaded: totalUploaded, downloaded: totalDownloaded,
            savePath: savePath
        )
    }

    /// Wait until metadata is available, or return immediately if already present.
    public func waitForMetadata(timeout seconds: Int) async throws -> TorrentInfo {
        if let info = self.info {
            return info
        }

        let id = nextWaitID
        nextWaitID += 1

        return try await withCheckedThrowingContinuation { continuation in
            metadataContinuations[id] = continuation

            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard let self else { return }
                if let cont = await self.removeMetadataContinuation(id: id) {
                    cont.resume(throwing: TorrentError.timeout)
                }
            }
        }
    }

    private func removeMetadataContinuation(id: UInt64) -> CheckedContinuation<TorrentInfo, Error>? {
        metadataContinuations.removeValue(forKey: id)
    }

    /// Wait until all pieces are downloaded, or return immediately if already complete.
    public func waitForCompletion(timeout seconds: Int) async throws {
        if state == .seeding {
            return
        }

        let id = nextWaitID
        nextWaitID += 1

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            completionContinuations[id] = continuation

            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard let self else { return }
                if let cont = await self.removeCompletionContinuation(id: id) {
                    cont.resume(throwing: TorrentError.timeout)
                }
            }
        }
    }

    private func removeCompletionContinuation(id: UInt64) -> CheckedContinuation<Void, Error>? {
        completionContinuations.removeValue(forKey: id)
    }
}
