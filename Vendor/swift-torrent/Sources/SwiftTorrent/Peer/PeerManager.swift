import Foundation
import NIOCore
import NIOPosix

/// Manages the pool of peer connections for a torrent.
public actor PeerManager {
    private let infoHash: Data
    private let peerID: Data
    private let group: EventLoopGroup
    private var connections: [String: PeerConnection] = [:]
    private var connectedPeers: Set<String> = []
    private var peerInfos: [String: PeerInfo] = [:]
    private var peerStates: [String: PeerState] = [:]
    private let maxConnections: Int

    public var pieceManager: PieceManager?
    public var piecePicker: PiecePicker?
    public var diskIO: DiskIO?
    public var metadataExchange: MetadataExchange?
    public var onPieceCompleted: ((Int) -> Void)?
    public var onMetadataReceived: ((TorrentInfo) -> Void)?

    private var pieceCount: Int = 0

    public init(infoHash: Data, peerID: Data, group: EventLoopGroup, maxConnections: Int = 50) {
        self.infoHash = infoHash
        self.peerID = peerID
        self.group = group
        self.maxConnections = maxConnections
    }

    public func configure(pieceManager: PieceManager, piecePicker: PiecePicker, diskIO: DiskIO, pieceCount: Int) {
        self.pieceManager = pieceManager
        self.piecePicker = piecePicker
        self.diskIO = diskIO
        self.pieceCount = pieceCount
    }

    /// Replace the live piece picker (value type). Callers must preserve
    /// availability state when only changing strategy/range.
    public func updatePiecePicker(_ picker: PiecePicker) {
        self.piecePicker = picker
    }

    /// Mutate the live piece picker in place.
    public func modifyPiecePicker(_ body: (inout PiecePicker) -> Void) {
        guard var picker = piecePicker else { return }
        body(&picker)
        piecePicker = picker
    }

    /// Update pick strategy/range, cancel in-flight block requests, and refill pipelines.
    public func applyPiecePriority(range: Range<Int>, mode: PiecePickMode) async {
        modifyPiecePicker { picker in
            picker.setPriority(range: range, mode: mode)
        }
        await cancelAllPendingRequests()
        for key in peerStates.keys {
            await fillRequests(for: key)
        }
    }

    private func cancelAllPendingRequests() async {
        for (key, state) in peerStates {
            let pending = await state.getPendingRequests()
            if let conn = connections[key] {
                for request in pending.keys {
                    try? await conn.send(.cancel(
                        index: UInt32(request.pieceIndex),
                        begin: UInt32(request.offset),
                        length: UInt32(request.length)
                    ))
                }
            }
            await state.clearPendingRequests()
        }
    }

    public func configureMagnet(metadataExchange: MetadataExchange) {
        self.metadataExchange = metadataExchange
    }

    public func setOnMetadataReceived(_ handler: @escaping (TorrentInfo) -> Void) {
        self.onMetadataReceived = handler
    }

    public func setOnPieceCompleted(_ handler: @escaping (Int) -> Void) {
        self.onPieceCompleted = handler
    }

    /// Drop all peers (e.g. after magnet metadata when pieceCount becomes known).
    public func disconnectAll() async {
        let keys = Array(connections.keys)
        for key in keys {
            if let conn = connections[key] {
                try? await conn.close()
            }
            removePeerByKey(key)
        }
    }

    /// Add a peer and attempt connection.
    public func addPeer(address: String, port: UInt16) async {
        let key = "\(address):\(port)"
        guard connections[key] == nil else { return }
        guard connections.count < maxConnections else { return }

        let conn = PeerConnection(address: address, port: port, infoHash: infoHash, peerID: peerID)
        connections[key] = conn
        peerInfos[key] = PeerInfo(id: Data(), address: address, port: port)

        // Create PeerState BEFORE connect completes. Peers send bitfield immediately
        // after handshake; if state is missing those messages are dropped and we
        // never learn which pieces they have (0 downloads forever).
        let pc = pieceCount > 0 ? pieceCount : 1
        let state = PeerState(pieceCount: pc)
        peerStates[key] = state
        await state.setAmInterested(true)

        // Set up message callbacks
        conn.onMessage = { [weak self] message in
            guard let self else { return }
            Task { await self.handleMessage(message, from: key) }
        }
        conn.onDisconnect = { [weak self] in
            guard let self else { return }
            Task { await self.handleDisconnect(key: key) }
        }

        Task {
            do {
                let _ = try await conn.connect(on: group)
                await self.onPeerConnected(key: key, conn: conn)
            } catch {
                await self.removePeerByKey(key)
            }
        }
    }

    private func onPeerConnected(key: String, conn: PeerConnection) async {
        connectedPeers.insert(key)

        // Keep existing state — it may already hold the peer's bitfield.
        if peerStates[key] == nil {
            let pc = pieceCount > 0 ? pieceCount : 1
            peerStates[key] = PeerState(pieceCount: pc)
        }
        if let state = peerStates[key] {
            await state.setAmInterested(true)
        }

        // Send our bitfield once we know the piece count (post-metadata).
        if pieceCount > 0 {
            let empty = Bitfield(count: pieceCount)
            try? await conn.send(.bitfield(empty.toData()))
        }

        // Send interested
        try? await conn.send(.interested)

        // If peer supports extensions and we need metadata, send extended handshake
        if conn.supportsExtensions, let metaEx = metadataExchange {
            let extHandshake = await metaEx.buildExtendedHandshake()
            try? await conn.send(.extended(id: 0, payload: extHandshake))
        }

        // Peer may already have unchoked us while state existed during handshake.
        await fillRequests(for: key)
    }

    private func handleDisconnect(key: String) {
        if let state = peerStates[key] {
            Task {
                let bf = await state.getPeerBitfield()
                if var picker = self.piecePicker {
                    picker.removePeerBitfield(bf)
                    self.piecePicker = picker
                }
            }
        }
        connections.removeValue(forKey: key)
        peerInfos.removeValue(forKey: key)
        peerStates.removeValue(forKey: key)
        connectedPeers.remove(key)
    }

    private func handleMessage(_ message: PeerMessage, from key: String) async {
        guard let state = peerStates[key] else { return }

        switch message {
        case .bitfield(let data):
            let bf = Bitfield(data: data, count: pieceCount > 0 ? pieceCount : data.count * 8)
            await state.setPeerBitfield(bf)
            if var picker = piecePicker {
                picker.addPeerBitfield(bf)
                piecePicker = picker
            }
            peerInfos[key]?.peerBitfield = bf
            await fillRequests(for: key)

        case .have(let pieceIndex):
            let idx = Int(pieceIndex)
            await state.setHave(idx)
            if var picker = piecePicker {
                picker.addHave(idx)
                piecePicker = picker
            }
            await fillRequests(for: key)

        case .choke:
            await state.setPeerChoking(true)
            await state.clearPendingRequests()

        case .unchoke:
            await state.setPeerChoking(false)
            await fillRequests(for: key)

        case .interested:
            await state.setPeerInterested(true)

        case .notInterested:
            await state.setPeerInterested(false)

        case .piece(let index, let begin, let block):
            let pieceIndex = Int(index)
            let offset = Int(begin)
            let request = PeerState.BlockRequest(pieceIndex: pieceIndex, offset: offset, length: block.count)
            await state.removePendingRequest(request)

            guard let pm = pieceManager else { break }
            await pm.addBlock(pieceIndex: pieceIndex, offset: offset, data: block)

            // Only verify when every block has arrived (buffer.length alone is wrong
            // for out-of-order blocks that pad the buffer with zeros).
            if await pm.hasAllBlocks(pieceIndex) {
                let expectedSize = await pm.expectedPieceSize(pieceIndex)
                if let buf = await pm.getPieceBuffer(pieceIndex), buf.count >= expectedSize {
                    await onPieceComplete(index: pieceIndex, data: buf)
                }
            }

            await fillRequests(for: key)

        case .extended(let extID, let payload):
            if let metaEx = metadataExchange {
                let result = await metaEx.handleExtendedMessage(id: extID, payload: payload)
                switch result {
                case .sendMessage(let msg):
                    try? await connections[key]?.send(msg)
                case .requestMore(let messages):
                    for msg in messages {
                        try? await connections[key]?.send(msg)
                    }
                case .metadataComplete(let info):
                    onMetadataReceived?(info)
                case .none:
                    break
                }
            }

        default:
            break
        }
    }

    private func fillRequests(for key: String) async {
        guard let state = peerStates[key],
              let pm = pieceManager,
              let conn = connections[key] else { return }

        let peerChoking = await state.getPeerChoking()
        guard !peerChoking else { return }

        let completed = await pm.getCompleted()

        while await state.canRequest {
            let peerBF = await state.getPeerBitfield()
            guard let picker = piecePicker,
                  let pieceIndex = picker.pick(have: completed, peerHas: peerBF) else { break }

            // Start piece if not in progress
            let inProg = await pm.isInProgress(pieceIndex)
            let hasPc = await pm.hasPiece(pieceIndex)
            if !inProg && !hasPc {
                await pm.startPiece(pieceIndex)
            }

            let pieceSize = await pm.expectedPieceSize(pieceIndex)
            let blockSize = 16384
            var offset = 0
            var sent = false
            while offset < pieceSize {
                let canReq = await state.canRequest
                guard canReq else { break }
                let length = min(blockSize, pieceSize - offset)
                if await pm.hasReceivedBlock(pieceIndex: pieceIndex, offset: offset) {
                    offset += blockSize
                    continue
                }
                let request = PeerState.BlockRequest(pieceIndex: pieceIndex, offset: offset, length: length)
                if !(await state.hasPending(request)) {
                    await state.addPendingRequest(request)
                    try? await conn.send(.request(
                        index: UInt32(pieceIndex),
                        begin: UInt32(offset),
                        length: UInt32(length)
                    ))
                    sent = true
                }
                offset += blockSize
            }
            if !sent { break } // Nothing left to request for this piece from this peer
            break // One piece at a time per fill cycle
        }
    }

    private func onPieceComplete(index pieceIndex: Int, data: Data) async {
        guard let pm = pieceManager else { return }
        let verified = await pm.completePiece(pieceIndex)
        if verified {
            // Write to disk
            if let dio = diskIO {
                try? await dio.writePiece(index: pieceIndex, data: data)
            }
            await broadcastHave(pieceIndex: UInt32(pieceIndex))
            onPieceCompleted?(pieceIndex)
        }
    }

    private func markConnected(key: String) {
        connectedPeers.insert(key)
    }

    private func removePeerByKey(_ key: String) {
        connections.removeValue(forKey: key)
        peerInfos.removeValue(forKey: key)
        peerStates.removeValue(forKey: key)
        connectedPeers.remove(key)
    }

    /// Remove a peer.
    public func removePeer(address: String, port: UInt16) async {
        let key = "\(address):\(port)"
        if let conn = connections.removeValue(forKey: key) {
            try? await conn.close()
        }
        peerInfos.removeValue(forKey: key)
        peerStates.removeValue(forKey: key)
        connectedPeers.remove(key)
    }

    /// Get all connected peer infos.
    public func peers() -> [PeerInfo] {
        Array(peerInfos.values)
    }

    /// Number of active connections.
    public var connectionCount: Int {
        connections.count
    }

    /// Number of peers that completed the TCP handshake.
    public var connectedCount: Int {
        connectedPeers.count
    }

    /// Implements the choking algorithm — unchoke top uploaders + one optimistic unchoke.
    public func runChokingAlgorithm() async {
        var peers = Array(peerInfos)
        peers.sort { $0.value.downloadRate > $1.value.downloadRate }

        let unchokeSlots = 4
        for (i, peer) in peers.enumerated() {
            var info = peer.value
            if i < unchokeSlots {
                info.amChoking = false
            } else if i == unchokeSlots {
                info.amChoking = false
            } else {
                info.amChoking = true
            }
            peerInfos[peer.key] = info
        }
    }

    /// Send interested message to all peers.
    public func sendInterestedToAll() async {
        let msg = PeerMessage.interested
        for (key, conn) in connections {
            guard connectedPeers.contains(key) else { continue }
            try? await conn.send(msg)
        }
    }

    /// Broadcast a have message to all peers.
    public func broadcastHave(pieceIndex: UInt32) async {
        let msg = PeerMessage.have(pieceIndex: pieceIndex)
        for (key, conn) in connections {
            guard connectedPeers.contains(key) else { continue }
            try? await conn.send(msg)
        }
    }

    /// Check for timed-out requests and cancel them.
    public func checkTimeouts() async {
        for (key, state) in peerStates {
            let timedOut = await state.timedOutRequests()
            for request in timedOut {
                await state.removePendingRequest(request)
            }
            if !timedOut.isEmpty {
                await fillRequests(for: key)
            }
        }
    }
}
