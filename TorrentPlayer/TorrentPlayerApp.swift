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
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(engine)
                    .opacity(showSplash ? 0 : 1)
                    .allowsHitTesting(!showSplash)

                if showSplash {
                    SplashScreenView(isReady: engine.isOperational) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showSplash = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
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
