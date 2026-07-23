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
    #if os(macOS)
    @NSApplicationDelegateAdaptor(TorrentPlayerAppDelegate.self) private var appDelegate
    #endif

    @State private var engine = TorrentEngine()
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Matches LaunchScreen / splash so the first SwiftUI frame is never system white.
                KTColor.background.ignoresSafeArea()

                ContentView()
                    .environment(engine)
                    .opacity(showSplash ? 0 : 1)
                    .allowsHitTesting(!showSplash)

                if showSplash {
                    SplashScreenView(
                        bootStep: engine.bootStep,
                        bootProgress: engine.bootProgress
                    ) {
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
            .background(WindowBackgroundFixer())
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                Task { await engine.persistResumeIfNeeded(force: true) }
            }
            #endif
        }
        .modelContainer(for: TorrentHistoryEntry.self)
    }
}

#if os(macOS)
/// Paint NSWindow before SwiftUI’s first layout to avoid a white flash into splash.
final class TorrentPlayerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            window.backgroundColor = LaunchScreenColor.background
            window.isOpaque = true
        }
    }
}

private enum LaunchScreenColor {
    static let background = NSColor(srgbRed: 0xF9 / 255, green: 0xF9 / 255, blue: 0xF9 / 255, alpha: 1)
}

/// Ensures the hosting window background matches splash as soon as the view attaches.
private struct WindowBackgroundFixer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.backgroundColor = LaunchScreenColor.background
            view.window?.isOpaque = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.backgroundColor = LaunchScreenColor.background
        nsView.window?.isOpaque = true
    }
}
#endif
