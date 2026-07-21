import Foundation

/// Maps piece indices to file regions for disk I/O.
public struct FileStorage: Sendable {
    public let files: [TorrentInfo.FileEntry]
    public let pieceLength: Int
    public let totalSize: Int64

    public init(files: [TorrentInfo.FileEntry], pieceLength: Int, totalSize: Int64) {
        self.files = files
        self.pieceLength = pieceLength
        self.totalSize = totalSize
    }

    public init(info: TorrentInfo) {
        self.files = info.files
        self.pieceLength = info.pieceLength
        self.totalSize = info.totalSize
    }

    /// A region within a single file that a piece (or part of a piece) maps to.
    public struct FileSlice: Sendable {
        public let fileIndex: Int
        public let path: String
        public let offset: Int64     // offset within the file
        public let length: Int
    }

    /// Get the file slices for a given piece index.
    public func fileSlices(forPiece pieceIndex: Int) -> [FileSlice] {
        let pieceStart = Int64(pieceIndex) * Int64(pieceLength)
        let pieceEnd = min(pieceStart + Int64(pieceLength), totalSize)
        let length = pieceEnd - pieceStart

        guard length > 0 else { return [] }

        var slices: [FileSlice] = []
        var remaining = length
        var currentOffset = pieceStart

        for (i, file) in files.enumerated() {
            let fileEnd = file.offset + file.length
            if currentOffset >= fileEnd { continue }
            if currentOffset < file.offset { continue }

            let offsetInFile = currentOffset - file.offset
            let available = min(Int64(remaining), file.length - offsetInFile)

            slices.append(FileSlice(
                fileIndex: i,
                path: file.path,
                offset: offsetInFile,
                length: Int(available)
            ))

            remaining -= available
            currentOffset += available
            if remaining <= 0 { break }
        }

        return slices
    }

    /// Total number of pieces.
    public var pieceCount: Int {
        guard pieceLength > 0 else { return 0 }
        return Int((totalSize + Int64(pieceLength) - 1) / Int64(pieceLength))
    }

    /// Piece index range covering `fileIndex` (half-open). Boundary pieces that
    /// also touch adjacent files are included — required for correct file I/O.
    public func pieceRange(forFileIndex fileIndex: Int) -> Range<Int>? {
        guard fileIndex >= 0, fileIndex < files.count, pieceLength > 0 else { return nil }
        let file = files[fileIndex]
        guard file.length > 0 else { return nil }

        let start = Int(file.offset / Int64(pieceLength))
        let lastByte = file.offset + file.length - 1
        let endExclusive = Int(lastByte / Int64(pieceLength)) + 1
        let clampedEnd = min(endExclusive, pieceCount)
        guard start < clampedEnd else { return nil }
        return start..<clampedEnd
    }

    /// Size of a specific piece (last piece may be smaller).
    public func pieceSize(_ index: Int) -> Int {
        let start = Int64(index) * Int64(pieceLength)
        return Int(min(Int64(pieceLength), totalSize - start))
    }

    /// Piece indices that must be complete to cover `[fileOffset, fileOffset + length)` within the file.
    public func pieceRange(
        forFileIndex fileIndex: Int,
        fileOffset: Int64,
        length: Int64
    ) -> Range<Int>? {
        guard fileIndex >= 0, fileIndex < files.count, pieceLength > 0 else { return nil }
        let file = files[fileIndex]
        guard file.length > 0, length > 0, fileOffset >= 0, fileOffset < file.length else { return nil }

        let need = min(length, file.length - fileOffset)
        let startByte = file.offset + fileOffset
        let lastByte = startByte + need - 1
        let start = Int(startByte / Int64(pieceLength))
        let endExclusive = Int(lastByte / Int64(pieceLength)) + 1
        let clampedEnd = min(endExclusive, pieceCount)
        guard start < clampedEnd else { return nil }
        return start..<clampedEnd
    }

    /// Piece indices that must be complete to cover the first `bytes` of `fileIndex`.
    /// Caps at the file length; returns nil for invalid index or empty file.
    public func leadingPieceRange(forFileIndex fileIndex: Int, bytes: Int64) -> Range<Int>? {
        pieceRange(forFileIndex: fileIndex, fileOffset: 0, length: bytes)
    }
}
