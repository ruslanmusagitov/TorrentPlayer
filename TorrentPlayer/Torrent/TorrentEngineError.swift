//
//  TorrentEngineError.swift
//  TorrentPlayer
//

import Foundation

enum TorrentEngineError: LocalizedError, Equatable {
    case emptyMagnet
    case sessionNotReady
    case unsupportedPlatform
    case metadataTimeout
    case noSelectedFile
    case playbackBufferTimeout
    case playbackServerFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyMagnet:
            "Magnet link is empty."
        case .sessionNotReady:
            "Torrent session is not ready yet."
        case .unsupportedPlatform:
            "Torrent engine is not available on this platform."
        case .metadataTimeout:
            "Timed out waiting for torrent metadata."
        case .noSelectedFile:
            "No video file selected for playback."
        case .playbackBufferTimeout:
            "Timed out waiting for enough video data to start playback."
        case let .playbackServerFailed(message):
            "Could not start local stream server: \(message)"
        }
    }
}
