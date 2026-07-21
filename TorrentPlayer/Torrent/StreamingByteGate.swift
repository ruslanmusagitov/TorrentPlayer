//
//  StreamingByteGate.swift
//  TorrentPlayer
//
//  Thread-safe "bytes ready through offset" for the HTTP streamer.
//  Keeps NWConnection handlers off the TorrentHandle actor (avoids stalls).
//

import Foundation

/// Tracks the highest contiguous file offset known to be on disk `[0, readyThrough)`.
final class StreamingByteGate: @unchecked Sendable {
    private let lock = NSLock()
    private var readyThrough: Int64 = 0

    func markReady(through offsetExclusive: Int64) {
        guard offsetExclusive > 0 else { return }
        lock.lock()
        readyThrough = max(readyThrough, offsetExclusive)
        lock.unlock()
    }

    func isReady(offset: Int64, length: Int64) -> Bool {
        guard length > 0, offset >= 0 else { return false }
        lock.lock()
        let ready = readyThrough
        lock.unlock()
        return offset + length <= ready
    }

    var readyThroughOffset: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return readyThrough
    }
}
