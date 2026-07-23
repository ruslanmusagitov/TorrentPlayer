import Foundation
import NIOCore

/// Waits for the remote BitTorrent handshake on an accepted TCP channel, then
/// forwards the channel to the session for torrent routing.
///
/// Buffers any peer messages that arrive in the same TCP packet as the handshake
/// until `PeerManager` attaches its handlers and drains them.
final class IncomingPeerHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = PeerMessage

    private let decoder: PeerMessageDecoder
    private let onHandshake: @Sendable (Channel, IncomingPeerHandler) -> Void
    private var waitTask: Task<Void, Never>?
    private var pendingMessages: [PeerMessage] = []
    private var handshakeDelivered = false
    private var forwarding = false
    private let lock = NSLock()

    init(
        decoder: PeerMessageDecoder,
        onHandshake: @escaping @Sendable (Channel, IncomingPeerHandler) -> Void
    ) {
        self.decoder = decoder
        self.onHandshake = onHandshake
    }

    var remoteInfoHash: Data? { decoder.remoteInfoHash }
    var remotePeerID: Data? { decoder.remotePeerID }
    var remoteSupportsExtensions: Bool { decoder.remoteSupportsExtensions }

    func takePendingMessages() -> [PeerMessage] {
        lock.lock()
        defer { lock.unlock() }
        let messages = pendingMessages
        pendingMessages.removeAll()
        return messages
    }

    /// After PeerManager attaches handlers, forward further messages down the pipeline.
    func beginForwarding() {
        lock.lock()
        forwarding = true
        lock.unlock()
    }

    func channelActive(context: ChannelHandlerContext) {
        let channel = context.channel
        let decoder = self.decoder

        waitTask = Task { [weak self] in
            let deadline = ContinuousClock.now + .seconds(10)
            while ContinuousClock.now < deadline {
                if Task.isCancelled { return }
                guard let self else { return }
                if decoder.isHandshakeReceived {
                    self.deliverHandshakeIfNeeded(channel: channel)
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            TorrentLog.peer("incoming handshake timeout")
            try? await channel.close().get()
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        lock.lock()
        if forwarding {
            lock.unlock()
            context.fireChannelRead(data)
            return
        }
        let message = unwrapInboundIn(data)
        pendingMessages.append(message)
        let shouldDeliver = !handshakeDelivered && decoder.isHandshakeReceived
        lock.unlock()

        if shouldDeliver {
            deliverHandshakeIfNeeded(channel: context.channel)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        waitTask?.cancel()
        waitTask = nil
    }

    private func deliverHandshakeIfNeeded(channel: Channel) {
        lock.lock()
        if handshakeDelivered {
            lock.unlock()
            return
        }
        handshakeDelivered = true
        lock.unlock()

        _ = channel.setOption(ChannelOptions.autoRead, value: false)
        onHandshake(channel, self)
    }

    static func remoteEndpoint(of channel: Channel) -> (String, UInt16) {
        guard let remote = channel.remoteAddress else {
            return ("0.0.0.0", 0)
        }
        let port = UInt16(remote.port ?? 0)
        switch remote {
        case .v4(let addr):
            return (addr.host, port)
        case .v6(let addr):
            return (addr.host, port)
        default:
            return (remote.description, port)
        }
    }
}
