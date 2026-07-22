//
//  TorrentPlayerApp.swift
//  TorrentPlayer
//

import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

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
                #if os(macOS)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    Task { await engine.persistResumeIfNeeded(force: true) }
                }
                #endif
        }
        .modelContainer(for: TorrentHistoryEntry.self)
    }
}
