//
//  ContentView.swift
//  TorrentPlayer
//
//  Root shell: header + side/bottom nav + four Kinetic Torrent screens.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var selection: AppDestination = .load
    /// Keeps StreamingPlayerView alive across tab switches only after the first Player visit.
    @State private var playerMounted = false
    /// In-place player fullscreen — hides shell chrome so the same video surface can expand.
    @State private var playerFullscreen = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(TorrentEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext

    private var usesSideNav: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            if !playerFullscreen {
                AppHeaderBar()
            }

            if usesSideNav {
                HStack(spacing: 0) {
                    if !playerFullscreen {
                        SideNavBar(selection: $selection)
                    }
                    destinationView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                destinationView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !playerFullscreen {
                    BottomNavBar(selection: $selection)
                }
            }
        }
        .background((playerFullscreen ? Color.black : KTColor.background).ignoresSafeArea())
        .onChange(of: selection) { _, newValue in
            if newValue == .player {
                playerMounted = true
            } else {
                playerFullscreen = false
            }
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 640)
        #endif
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = Self.torrentURL(from: activity) {
                IncomingTorrentFiles.handle([url])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: IncomingTorrentFiles.didReceive)) { _ in
            Task { await consumePendingTorrentFiles() }
        }
        .onChange(of: engine.phase) { _, _ in
            guard engine.isOperational, IncomingTorrentFiles.hasPending else { return }
            Task { await consumePendingTorrentFiles() }
        }
        .task {
            await consumePendingTorrentFiles()
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        let playerActive = selection == .player
        // Lock both layers to the container size so a kept-alive Player cannot
        // inflate ideal width (layout bug on iPhone) while still hosting AV/VLC
        // as a real ZStack child (overlay broke video playback).
        GeometryReader { geo in
            ZStack {
                tabContent
                    .frame(width: geo.size.width, height: geo.size.height)

                if playerMounted || playerActive {
                    StreamingPlayerView(isActive: playerActive, isFullscreen: $playerFullscreen)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .opacity(playerActive ? 1 : 0)
                        .allowsHitTesting(playerActive)
                        .accessibilityHidden(!playerActive)
                        .zIndex(playerActive ? 1 : 0)
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selection {
        case .load:
            LoadMagnetView {
                selection = .files
            }
        case .files:
            SelectFileView {
                selection = .player
            }
        case .player:
            Color.clear
        case .history:
            TorrentHistoryView {
                selection = .files
            }
        }
    }

    private func consumePendingTorrentFiles() async {
        await IncomingTorrentFiles.consumeExclusively {
            while IncomingTorrentFiles.hasPending {
                guard await waitUntilEngineOperational() else {
                    if case .unsupportedPlatform = engine.phase {
                        IncomingTorrentFiles.discardLatest()
                        TPLog.error("dropped queued torrent file: torrent engine unavailable")
                    } else {
                        TPLog.error("engine not ready; keeping queued torrent file")
                    }
                    return
                }
                guard let url = IncomingTorrentFiles.takeLatest() else { return }
                await openIncomingURL(url)
            }
        }
    }

    private func openIncomingURL(_ url: URL) async {
        guard IncomingTorrentFiles.isTorrentFileURL(url) else {
            IncomingTorrentFiles.removeConsumedCopyIfNeeded(url)
            return
        }
        do {
            try await TorrentHistoryEntry.addTorrentFile(url: url, using: engine, in: modelContext)
            selection = .files
        } catch {
            // Engine already set .error for UI feedback (keeps previous torrent if any).
            // Keep Inbox/staging copies so a broken file can be opened again.
        }
    }

    private func waitUntilEngineOperational(timeout: Duration = .seconds(15)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if engine.isOperational { return true }
            if case .unsupportedPlatform = engine.phase { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return engine.isOperational
    }

    private static func torrentURL(from activity: NSUserActivity) -> URL? {
        if let url = activity.webpageURL, IncomingTorrentFiles.isTorrentFileURL(url) {
            return url
        }
        #if os(macOS)
        if let url = activity.userInfo?[NSUserActivityDocumentURLKey] as? URL,
           IncomingTorrentFiles.isTorrentFileURL(url) {
            return url
        }
        #endif
        return nil
    }
}

#Preview {
    ContentView()
        .environment(TorrentEngine())
        .modelContainer(for: TorrentHistoryEntry.self, inMemory: true)
}
