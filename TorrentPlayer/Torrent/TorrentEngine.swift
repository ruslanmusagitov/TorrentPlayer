//
//  TorrentEngine.swift
//  TorrentPlayer
//
//  Task #3: torrent session on macOS (SwiftTorrent SPM).
//  Task #4: metadata fetch and file list.
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
        case fetchingMetadata
        case loaded(ActiveTorrent)
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastMagnetURI: String?
    private(set) var activeTorrent: ActiveTorrent?

    #if os(macOS)
    private var session: Session?
    private var activeHandle: TorrentHandle?
    private var activeInfoHash: InfoHash?
    #endif

    private let metadataTimeoutSeconds: Int

    init(metadataTimeoutSeconds: Int = 90) {
        self.metadataTimeoutSeconds = metadataTimeoutSeconds
    }

    var isLoadingTorrent: Bool {
        switch phase {
        case .adding, .fetchingMetadata:
            true
        default:
            false
        }
    }

    var isOperational: Bool {
        switch phase {
        case .ready, .loaded, .error:
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
        case .fetchingMetadata:
            "Fetching Metadata…"
        case let .loaded(torrent):
            "Loaded • \(torrent.files.count) Files"
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
            phase = .error(TorrentEngineError.emptyMagnet.localizedDescription)
            throw TorrentEngineError.emptyMagnet
        }

        #if os(macOS)
        guard let session else {
            phase = .error(TorrentEngineError.sessionNotReady.localizedDescription)
            throw TorrentEngineError.sessionNotReady
        }

        let previousTorrent = activeTorrent
        let previousInfoHash = activeInfoHash

        phase = .adding
        var pendingInfoHash: InfoHash?

        do {
            let downloads = try Self.downloadsDirectory()
            let params = try AddTorrentParams.fromMagnet(trimmed, savePath: downloads.path)
            guard let infoHash = params.infoHash else {
                throw AddTorrentError.noInfoHash
            }
            pendingInfoHash = infoHash

            let handle = try await session.addTorrent(params)
            activeHandle = handle

            phase = .fetchingMetadata
            let info: TorrentInfo
            do {
                info = try await handle.waitForMetadata(timeout: metadataTimeoutSeconds)
            } catch is TorrentError {
                await session.removeTorrent(infoHash)
                pendingInfoHash = nil
                activeHandle = nil
                activeInfoHash = previousInfoHash
                failOrRestore(
                    previousTorrent: previousTorrent,
                    message: TorrentEngineError.metadataTimeout.localizedDescription
                )
                throw TorrentEngineError.metadataTimeout
            }

            if let previousInfoHash, previousInfoHash != infoHash {
                await session.removeTorrent(previousInfoHash)
            }

            let hash = infoHash.description
            let torrent = ActiveTorrent.from(info: info, infoHash: hash)
            activeTorrent = torrent
            activeInfoHash = infoHash
            lastMagnetURI = trimmed
            pendingInfoHash = nil
            phase = .loaded(torrent)
        } catch let error as TorrentEngineError {
            if case .metadataTimeout = error {
                throw error
            }
            if let pendingInfoHash {
                await session.removeTorrent(pendingInfoHash)
            }
            activeHandle = nil
            activeInfoHash = previousInfoHash
            failOrRestore(previousTorrent: previousTorrent, message: error.localizedDescription)
            throw error
        } catch {
            if let pendingInfoHash {
                await session.removeTorrent(pendingInfoHash)
            }
            activeHandle = nil
            activeInfoHash = previousInfoHash
            failOrRestore(previousTorrent: previousTorrent, message: error.localizedDescription)
            throw error
        }
        #else
        phase = .error(TorrentEngineError.unsupportedPlatform.localizedDescription)
        throw TorrentEngineError.unsupportedPlatform
        #endif
    }

    #if os(macOS)
    private func failOrRestore(previousTorrent: ActiveTorrent?, message: String) {
        if let previousTorrent {
            activeTorrent = previousTorrent
            phase = .loaded(previousTorrent)
        } else {
            phase = .error(message)
        }
    }
    #endif

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
