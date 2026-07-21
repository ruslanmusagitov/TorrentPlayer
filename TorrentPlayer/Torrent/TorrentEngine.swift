//
//  TorrentEngine.swift
//  TorrentPlayer
//
//  Task #3: torrent session on macOS (SwiftTorrent SPM).
//

import Foundation
import Observation
#if os(macOS)
import SwiftTorrent
#endif

@MainActor
@Observable
final class TorrentEngine {
    enum Phase: Equatable {
        case idle
        case starting
        case ready
        case unsupportedPlatform
        case adding
        case added(displayName: String, infoHash: String)
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastMagnetURI: String?

    #if os(macOS)
    private var session: Session?
    #endif

    var isOperational: Bool {
        switch phase {
        case .ready, .added:
            true
        default:
            false
        }
    }

    var statusLabel: String {
        switch phase {
        case .idle:
            "System Idle"
        case .starting:
            "Starting Session…"
        case .ready:
            "System Ready"
        case .unsupportedPlatform:
            "Torrent Engine: macOS Only (iOS Soon)"
        case .adding:
            "Accepting Magnet…"
        case .added:
            "Magnet Accepted"
        case let .error(message):
            "Error: \(message)"
        }
    }

    func bootstrap() async {
        guard case .idle = phase else { return }
        phase = .starting

        #if os(macOS)
        do {
            let downloads = try Self.downloadsDirectory()
            let settings = SessionSettings(
                listenPort: 6881,
                dhtEnabled: true,
                savePath: downloads.path
            )
            let session = Session(settings: settings)
            do {
                try await session.startDHT()
            } catch {
                // DHT is optional for magnets that include tracker URLs.
            }
            self.session = session
            phase = .ready
        } catch {
            phase = .error(error.localizedDescription)
        }
        #else
        phase = .unsupportedPlatform
        #endif
    }

    func addMagnet(_ uri: String) async throws {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TorrentEngineError.emptyMagnet
        }

        #if os(macOS)
        guard let session else {
            throw TorrentEngineError.sessionNotReady
        }

        phase = .adding
        do {
            let downloads = try Self.downloadsDirectory()
            let params = try AddTorrentParams.fromMagnet(trimmed, savePath: downloads.path)
            let handle = try await session.addTorrent(params)
            let status = await handle.status()
            let name = params.magnetLink?.displayName ?? status.name
            let hash = params.infoHash.map(\.description) ?? status.infoHash.description

            lastMagnetURI = trimmed
            phase = .added(displayName: name, infoHash: hash)
        } catch {
            phase = .ready
            throw error
        }
        #else
        throw TorrentEngineError.unsupportedPlatform
        #endif
    }

    static func downloadsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("TorrentPlayer/Downloads", isDirectory: true)

        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
