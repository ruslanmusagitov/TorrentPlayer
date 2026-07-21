//
//  TorrentPlayerApp.swift
//  TorrentPlayer
//

import SwiftUI

@main
struct TorrentPlayerApp: App {
    @State private var engine = TorrentEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                .task {
                    await engine.bootstrap()
                }
        }
    }
}
