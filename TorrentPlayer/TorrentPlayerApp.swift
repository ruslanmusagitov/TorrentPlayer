//
//  TorrentPlayerApp.swift
//  TorrentPlayer
//

import SwiftData
import SwiftUI

@main
struct TorrentPlayerApp: App {
    @State private var engine = TorrentEngine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                .task {
                    TPLog.bootstrapFileLogging()
                    await engine.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .background || phase == .inactive else { return }
                    Task { await engine.persistResumeIfNeeded(force: true) }
                }
        }
        .modelContainer(for: TorrentHistoryEntry.self)
    }
}
