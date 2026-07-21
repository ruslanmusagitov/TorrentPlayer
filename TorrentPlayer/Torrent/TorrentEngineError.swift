//
//  TorrentEngineError.swift
//  TorrentPlayer
//

import Foundation

enum TorrentEngineError: LocalizedError {
    case emptyMagnet
    case sessionNotReady
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .emptyMagnet:
            "Magnet link is empty."
        case .sessionNotReady:
            "Torrent session is not ready yet."
        case .unsupportedPlatform:
            "Torrent engine is available on macOS only for now."
        }
    }
}
