//
//  StreamingByteGate.swift
//  TorrentPlayer
//
//  Thread-safe byte readiness for the HTTP streamer.
//  Keeps NWConnection handlers off the TorrentHandle actor (avoids stalls).
//
//  Supports a contiguous prefix plus extra ranges (e.g. MKV cues at EOF for VLC).
//

import Foundation

/// Tracks which file offsets are known to be on disk for progressive HTTP streaming.
final class StreamingByteGate: @unchecked Sendable {
    private let lock = NSLock()
    /// Merged half-open intervals `[start, end)`.
    private var intervals: [(Int64, Int64)] = []

    /// Marks `[0, offsetExclusive)` ready (grows the contiguous prefix).
    func markReady(through offsetExclusive: Int64) {
        guard offsetExclusive > 0 else { return }
        markReady(range: 0..<offsetExclusive)
    }

    /// Marks an arbitrary half-open byte range ready (merged with existing coverage).
    func markReady(range: Range<Int64>) {
        guard !range.isEmpty, range.lowerBound >= 0 else { return }
        lock.lock()
        intervals = Self.merged(intervals + [(range.lowerBound, range.upperBound)])
        lock.unlock()
    }

    func isReady(offset: Int64, length: Int64) -> Bool {
        guard length > 0, offset >= 0 else { return false }
        let end = offset + length
        lock.lock()
        let coverage = intervals
        lock.unlock()
        return Self.covers(coverage, start: offset, end: end)
    }

    /// Highest exclusive offset of the contiguous `[0, …)` prefix, if any.
    var readyThroughOffset: Int64 {
        lock.lock()
        defer { lock.unlock() }
        guard let first = intervals.first, first.0 == 0 else { return 0 }
        return first.1
    }

    private static func covers(_ intervals: [(Int64, Int64)], start: Int64, end: Int64) -> Bool {
        var cursor = start
        for (lo, hi) in intervals {
            if hi <= cursor { continue }
            if lo > cursor { return false }
            cursor = max(cursor, hi)
            if cursor >= end { return true }
        }
        return cursor >= end
    }

    private static func merged(_ input: [(Int64, Int64)]) -> [(Int64, Int64)] {
        let sorted = input
            .filter { $0.1 > $0.0 }
            .sorted { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
        guard var current = sorted.first else { return [] }
        var result: [(Int64, Int64)] = []
        for next in sorted.dropFirst() {
            if next.0 <= current.1 {
                current.1 = max(current.1, next.1)
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }
}
