//
//  TorrentEngineTests.swift
//  TorrentPlayerTests
//

import Testing
@testable import TorrentPlayer
#if os(macOS)
import SwiftTorrent
#endif

struct TorrentEngineTests {
    #if os(macOS)
    @Test func magnetParamsAcceptValidURI() throws {
        let magnet = "magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12&dn=Example"
        let params = try AddTorrentParams.fromMagnet(magnet, savePath: "/tmp")
        #expect(params.magnetLink?.displayName == "Example")
        #expect(params.infoHash?.description == "abcdef1234567890abcdef1234567890abcdef12")
    }

    @Test func magnetParamsRejectInvalidURI() {
        #expect(throws: AddTorrentError.self) {
            _ = try AddTorrentParams.fromMagnet("not-a-magnet", savePath: "/tmp")
        }
    }
    #endif

    @Test @MainActor func bootstrapLeavesEngineReadyOnMacOS() async {
        #if os(macOS)
        let engine = TorrentEngine()
        await engine.bootstrap()
        #expect(engine.isOperational)
        #else
        let engine = TorrentEngine()
        await engine.bootstrap()
        if case let .error(message) = engine.phase {
            #expect(message.contains("macOS"))
        } else {
            Issue.record("Expected unsupported platform error on non-macOS")
        }
        #endif
    }

    @Test @MainActor func addMagnetAcceptsValidURIOnMacOS() async throws {
        #if os(macOS)
        let engine = TorrentEngine()
        await engine.bootstrap()

        let magnet = "magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12&dn=Example"
        try await engine.addMagnet(magnet)

        if case let .added(name, hash) = engine.phase {
            #expect(name == "Example")
            #expect(hash == "abcdef1234567890abcdef1234567890abcdef12")
        } else {
            Issue.record("Expected added phase after valid magnet, got \(engine.phase)")
        }
        #else
        #expect(Bool(true))
        #endif
    }

    @Test @MainActor func addMagnetRejectsInvalidURIOnMacOS() async {
        #if os(macOS)
        let engine = TorrentEngine()
        await engine.bootstrap()

        await #expect(throws: AddTorrentError.self) {
            try await engine.addMagnet("not-a-magnet")
        }
        #else
        #expect(Bool(true))
        #endif
    }
}
