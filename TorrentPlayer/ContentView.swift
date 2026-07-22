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
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var usesSideNav: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            AppHeaderBar()

            if usesSideNav {
                HStack(spacing: 0) {
                    SideNavBar(selection: $selection)
                    destinationView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                destinationView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                BottomNavBar(selection: $selection)
            }
        }
        .background(KTColor.background.ignoresSafeArea())
        .onChange(of: selection) { _, newValue in
            if newValue == .player {
                playerMounted = true
            }
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 640)
        #endif
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
                    StreamingPlayerView(isActive: playerActive)
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
}

#Preview {
    ContentView()
        .environment(TorrentEngine())
        .modelContainer(for: TorrentHistoryEntry.self, inMemory: true)
}
