import Foundation
import NIOCore
import NIOPosix

/// Top-level controller for managing torrents.
public actor Session {
    private var settings: SessionSettings
    private var torrents: [InfoHash: TorrentHandle] = [:]
    private let group: MultiThreadedEventLoopGroup
    private var dhtNode: DHTNode?
    private var listenChannel: Channel?
    private var dhtDiscoveryTasks: [InfoHash: Task<Void, Never>] = [:]
    private let alertContinuation: AsyncStream<any Alert>.Continuation
    public let alerts: AsyncStream<any Alert>

    public init(settings: SessionSettings = SessionSettings()) {
        self.settings = settings
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        let (stream, continuation) = AsyncStream<any Alert>.makeStream()
        self.alerts = stream
        self.alertContinuation = continuation
    }

    /// Add a torrent to the session.
    public func addTorrent(_ params: AddTorrentParams) async throws -> TorrentHandle {
        guard let hash = params.infoHash else {
            throw AddTorrentError.noInfoHash
        }
        if let existing = torrents[hash] {
            return existing
        }

        let handle = TorrentHandle(params: params, settings: settings, group: group)
        await handle.finishInitialization()
        torrents[hash] = handle

        alertContinuation.yield(TorrentAddedAlert(
            infoHash: hash,
            name: params.torrentInfo?.name ?? params.magnetLink?.displayName ?? "Unknown"
        ))

        if !params.paused {
            try await handle.start()
            startDHTPeerDiscovery(for: hash)
        }

        return handle
    }

    /// Remove a torrent from the session.
    public func removeTorrent(_ infoHash: InfoHash, deleteFiles: Bool = false) async {
        dhtDiscoveryTasks.removeValue(forKey: infoHash)?.cancel()
        guard let handle = torrents.removeValue(forKey: infoHash) else { return }
        await handle.pause()

        if deleteFiles {
            let _ = await handle.status()
            // Delete files from disk
            let path = settings.savePath
            try? FileManager.default.removeItem(atPath: path)
        }

        alertContinuation.yield(TorrentRemovedAlert(infoHash: infoHash))
    }

    /// Get a torrent handle by info hash.
    public func torrent(for infoHash: InfoHash) -> TorrentHandle? {
        torrents[infoHash]
    }

    /// Get all torrent handles.
    public func allTorrents() -> [TorrentHandle] {
        Array(torrents.values)
    }

    /// Get status of all torrents.
    public func allStatus() async -> [TorrentStatus] {
        var statuses: [TorrentStatus] = []
        for handle in torrents.values {
            statuses.append(await handle.status())
        }
        return statuses
    }

    /// Update session settings and apply live seeding flag to all torrents.
    public func updateSettings(_ newSettings: SessionSettings) async {
        self.settings = newSettings
        for handle in torrents.values {
            await handle.setSeedingEnabled(newSettings.seedingEnabled)
        }
    }

    /// Toggle seeding for the whole session (persists in settings).
    public func setSeedingEnabled(_ enabled: Bool) async {
        settings.seedingEnabled = enabled
        for handle in torrents.values {
            await handle.setSeedingEnabled(enabled)
        }
        TorrentLog.session("session seedingEnabled=\(enabled)")
    }

    /// Bind TCP listen port for inbound peer connections.
    public func startListening() async throws {
        guard settings.listenPort > 0 else { return }
        guard listenChannel == nil else { return }

        let port = settings.listenPort
        let onHandshake: @Sendable (Channel, IncomingPeerHandler) -> Void = { channel, handler in
            Task { [weak self] in
                await self?.handleIncomingPeer(channel: channel, handler: handler)
            }
        }

        listenChannel = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let decoder = PeerMessageDecoder()
                let incoming = IncomingPeerHandler(decoder: decoder, onHandshake: onHandshake)
                return channel.pipeline.addHandlers([
                    ByteToMessageHandler(decoder),
                    incoming,
                ])
            }
            .bind(host: "0.0.0.0", port: Int(port))
            .get()

        TorrentLog.session("listening for peers on port \(port)")
    }

    /// Start DHT if enabled.
    public func startDHT() async throws {
        guard settings.dhtEnabled else { return }
        let node = DHTNode(port: settings.dhtPort, group: group)
        try await node.start()
        self.dhtNode = node
        TorrentLog.session("DHT started on port \(settings.dhtPort)")
    }

    /// Pause all torrents.
    public func pauseAll() async {
        for handle in torrents.values {
            await handle.pause()
        }
    }

    /// Resume all torrents.
    public func resumeAll() async throws {
        for handle in torrents.values {
            try await handle.resume()
            startDHTPeerDiscovery(for: await handle.infoHash)
        }
    }

    /// Shutdown the session.
    public func shutdown() async throws {
        for task in dhtDiscoveryTasks.values {
            task.cancel()
        }
        dhtDiscoveryTasks.removeAll()
        await pauseAll()
        if let listenChannel {
            try? await listenChannel.close().get()
            self.listenChannel = nil
        }
        alertContinuation.finish()
        try await group.shutdownGracefully()
    }

    // MARK: - Incoming peers

    private func handleIncomingPeer(channel: Channel, handler: IncomingPeerHandler) async {
        guard let infoHashBytes = handler.remoteInfoHash,
              let remotePeerID = handler.remotePeerID else {
            try? await channel.close().get()
            return
        }
        let hash = InfoHash(bytes: infoHashBytes)
        let (address, port) = IncomingPeerHandler.remoteEndpoint(of: channel)
        guard let torrentHandle = torrents[hash] else {
            TorrentLog.peer("incoming rejected \(address):\(port) — unknown infoHash=\(hash)")
            try? await channel.close().get()
            return
        }
        TorrentLog.peer("incoming OK \(address):\(port) infoHash=\(hash)")
        let pending = handler.takePendingMessages()
        await torrentHandle.acceptIncomingPeer(
            channel: channel,
            address: address,
            port: port,
            remotePeerID: remotePeerID,
            supportsExtensions: handler.remoteSupportsExtensions,
            pendingMessages: pending
        )
        handler.beginForwarding()
    }

    // MARK: - DHT peer discovery

    private func startDHTPeerDiscovery(for infoHash: InfoHash) {
        guard settings.dhtEnabled else { return }
        dhtDiscoveryTasks[infoHash]?.cancel()
        dhtDiscoveryTasks[infoHash] = Task { [weak self] in
            // Let bootstrap populate the routing table.
            try? await Task.sleep(for: .seconds(2))
            var round = 0
            while !Task.isCancelled {
                guard let self else { return }
                let found = await self.runDHTPeerLookup(infoHash: infoHash)
                TorrentLog.session("DHT get_peers round=\(round) infoHash=\(infoHash) peers=\(found)")
                round += 1
                // Re-query periodically; back off after the first few rounds.
                let delay: Duration = round < 4 ? .seconds(20) : .seconds(60)
                try? await Task.sleep(for: delay)
            }
        }
    }

    private func runDHTPeerLookup(infoHash: InfoHash) async -> Int {
        guard let node = dhtNode, let handle = torrents[infoHash] else { return 0 }
        let traversal = DHTTraversal(dhtNode: node)
        // Warm the routing table toward this info hash when still sparse.
        if await node.nodeCount() < 8 {
            let target = NodeID(bytes: Data(infoHash.bytes.prefix(20)))
            _ = try? await traversal.findNode(target: target)
        }
        guard let peers = try? await traversal.getPeers(infoHash: infoHash), !peers.isEmpty else {
            return 0
        }
        for (address, port) in peers {
            await handle.addPeer(address: address, port: port)
        }
        return peers.count
    }
}
