//
//  TorrentPlayerApp.swift
//  TorrentPlayer
//

import SwiftData
import SwiftUI

@main
struct TorrentPlayerApp: App {
    @State private var engine = TorrentEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                .task {
                    TPLog.bootstrapFileLogging()
                    await engine.bootstrap()
                }
        }
        .modelContainer(for: TorrentHistoryEntry.self)
    }
}
