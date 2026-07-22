//
//  ContentView.swift
//  TorrentPlayer
//
//  Root shell: header + side/bottom nav + four Kinetic Torrent stubs.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var selection: AppDestination = .load
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
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 640)
        #endif
    }

    @ViewBuilder
    private var destinationView: some View {
        let playerActive = selection == .player
        ZStack {
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

            StreamingPlayerView(isActive: playerActive)
                .opacity(playerActive ? 1 : 0)
                .allowsHitTesting(playerActive)
                .accessibilityHidden(!playerActive)
                .zIndex(playerActive ? 1 : 0)
        }
    }
}

#Preview {
    ContentView()
        .environment(TorrentEngine())
        .modelContainer(for: TorrentHistoryEntry.self, inMemory: true)
}
