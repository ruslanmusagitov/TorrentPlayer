import Foundation

/// Piece selection strategy.
public enum PiecePickMode: Sendable, Equatable {
    /// Classic BitTorrent rarest-first across all (or interested) pieces.
    case rarestFirst
    /// Prefer the lowest missing piece index (start → end) within the interested range.
    case sequential
}

/// Rarest-first / sequential piece selection strategy.
public struct PiecePicker: Sendable {
    private let pieceCount: Int
    private var availability: [Int]  // how many peers have each piece
    private var mode: PiecePickMode = .rarestFirst
    /// When set, only pieces in this range are eligible for download.
    private var interestedRange: Range<Int>?

    public init(pieceCount: Int) {
        self.pieceCount = pieceCount
        self.availability = [Int](repeating: 0, count: pieceCount)
    }

    /// Restrict downloads to `range` and pick pieces sequentially (lowest index first).
    public mutating func setSequential(range: Range<Int>) {
        setPriority(range: range, mode: .sequential)
    }

    /// Restrict downloads to `range` with the given pick mode.
    public mutating func setPriority(range: Range<Int>, mode: PiecePickMode) {
        self.mode = mode
        interestedRange = clamped(range)
    }

    /// Clear file/sequential restrictions; resume rarest-first over all pieces.
    public mutating func clearPriority() {
        mode = .rarestFirst
        interestedRange = nil
    }

    public var pickMode: PiecePickMode { mode }
    public var interestedPieceRange: Range<Int>? { interestedRange }

    /// Update availability from a peer's bitfield.
    public mutating func addPeerBitfield(_ bitfield: Bitfield) {
        for i in 0..<min(pieceCount, bitfield.count) {
            if bitfield.get(i) {
                availability[i] += 1
            }
        }
    }

    /// Remove a peer's bitfield from availability counts.
    public mutating func removePeerBitfield(_ bitfield: Bitfield) {
        for i in 0..<min(pieceCount, bitfield.count) {
            if bitfield.get(i) {
                availability[i] = max(0, availability[i] - 1)
            }
        }
    }

    /// Increment availability for a single piece (peer sent "have").
    public mutating func addHave(_ pieceIndex: Int) {
        guard pieceIndex >= 0 && pieceIndex < pieceCount else { return }
        availability[pieceIndex] += 1
    }

    /// Pick the next piece to request.
    /// `have` is our own bitfield; `peerHas` is the peer's bitfield.
    public func pick(have: Bitfield, peerHas: Bitfield) -> Int? {
        switch mode {
        case .sequential:
            return pickSequential(have: have, peerHas: peerHas)
        case .rarestFirst:
            return pickRarestFirst(have: have, peerHas: peerHas)
        }
    }

    /// Pick multiple pieces (for pipelining).
    public func pickMultiple(have: Bitfield, peerHas: Bitfield, count: Int) -> [Int] {
        guard count > 0 else { return [] }

        switch mode {
        case .sequential:
            var result: [Int] = []
            var simulatedHave = have
            for _ in 0..<count {
                guard let index = pickSequential(have: simulatedHave, peerHas: peerHas) else { break }
                result.append(index)
                simulatedHave.set(index)
            }
            return result
        case .rarestFirst:
            var candidates: [(index: Int, avail: Int)] = []
            for i in eligibleIndices {
                if !have.get(i) && peerHas.get(i) {
                    candidates.append((i, availability[i]))
                }
            }
            candidates.sort { $0.avail < $1.avail }
            return Array(candidates.prefix(count).map(\.index))
        }
    }

    // MARK: - Private

    private var eligibleIndices: Range<Int> {
        interestedRange ?? (0..<pieceCount)
    }

    private func clamped(_ range: Range<Int>) -> Range<Int> {
        let lower = max(0, range.lowerBound)
        let upper = min(pieceCount, range.upperBound)
        if lower >= upper { return lower..<lower }
        return lower..<upper
    }

    private func pickSequential(have: Bitfield, peerHas: Bitfield) -> Int? {
        for i in eligibleIndices {
            if !have.get(i) && peerHas.get(i) {
                return i
            }
        }
        return nil
    }

    private func pickRarestFirst(have: Bitfield, peerHas: Bitfield) -> Int? {
        var best: Int?
        var bestAvail = Int.max

        for i in eligibleIndices {
            if !have.get(i) && peerHas.get(i) {
                if availability[i] < bestAvail {
                    bestAvail = availability[i]
                    best = i
                }
            }
        }

        return best
    }
}
