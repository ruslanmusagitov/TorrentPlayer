//
//  TorrentFileItem.swift
//  TorrentPlayer
//
//  Task #4: torrent file list model and formatting.
//

import Foundation
#if os(macOS)
import SwiftTorrent
#endif

struct TorrentFileItem: Identifiable, Equatable, Sendable {
    let id: Int
    /// Relative path within the torrent (may include directories).
    let path: String
    let name: String
    let size: Int64
    let detail: String

    var isVideo: Bool {
        TorrentFileFormatting.isVideoExtension(
            (name as NSString).pathExtension
        )
    }
}

struct ActiveTorrent: Equatable, Sendable {
    let displayName: String
    let infoHash: String
    let totalSize: Int64
    let files: [TorrentFileItem]

    var formattedTotalSize: String {
        TorrentFileFormatting.formatSize(totalSize)
    }

    var videoFiles: [TorrentFileItem] {
        files.filter(\.isVideo)
    }

    var defaultSelectedFileID: Int? {
        videoFiles.first?.id
    }
}

enum TorrentFileFormatting {
    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter
    }()

    static func formatSize(_ bytes: Int64) -> String {
        sizeFormatter.string(fromByteCount: bytes)
    }

    static func fileName(from path: String) -> String {
        (path as NSString).lastPathComponent
    }

    static func fileDetail(size: Int64, path: String) -> String {
        let ext = (path as NSString).pathExtension.uppercased()
        return "\(formatSize(size)) • \(mediaKind(forExtension: ext))"
    }

    static func isVideoExtension(_ ext: String) -> Bool {
        switch ext.lowercased() {
        case "mkv", "mp4", "avi", "mov", "wmv", "flv", "webm", "m4v":
            true
        default:
            false
        }
    }

    static func makeFileItem(index: Int, path: String, length: Int64) -> TorrentFileItem {
        TorrentFileItem(
            id: index,
            path: path,
            name: fileName(from: path),
            size: length,
            detail: fileDetail(size: length, path: path)
        )
    }

    static func makeActiveTorrent(
        displayName: String,
        infoHash: String,
        totalSize: Int64,
        fileEntries: [(path: String, length: Int64)]
    ) -> ActiveTorrent {
        let files = fileEntries.enumerated().map { index, entry in
            makeFileItem(index: index, path: entry.path, length: entry.length)
        }
        return ActiveTorrent(
            displayName: displayName,
            infoHash: infoHash,
            totalSize: totalSize,
            files: files
        )
    }

    static func mediaKind(forExtension ext: String) -> String {
        switch ext {
        case "MKV", "MP4", "AVI", "MOV", "WEBM", "M4V", "WMV", "FLV":
            "Video/\(ext)"
        case "SRT", "VTT", "ASS":
            "Text/\(ext)"
        case "JPG", "JPEG", "PNG", "GIF", "WEBP":
            "Image/\(ext.isEmpty ? "JPG" : ext)"
        case "TXT", "NFO":
            "Text/\(ext.isEmpty ? "Plain" : ext)"
        case "":
            "File"
        default:
            ext
        }
    }
}

#if os(macOS)
extension ActiveTorrent {
    static func from(info: TorrentInfo, infoHash: String) -> ActiveTorrent {
        TorrentFileFormatting.makeActiveTorrent(
            displayName: info.name,
            infoHash: infoHash,
            totalSize: info.totalSize,
            fileEntries: info.files.map { ($0.path, $0.length) }
        )
    }
}
#endif
