//
//  TorrentPlayerApp.swift
//  TorrentPlayer
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers
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
            .onOpenURL { url in
                IncomingTorrentFiles.handle([url])
            }
            .dropDestination(for: URL.self) { urls, _ in
                IncomingTorrentFiles.handle(urls)
                return urls.contains { IncomingTorrentFiles.isTorrentFileURL($0) }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                var accepted = false
                for provider in providers where provider.canLoadObject(ofClass: URL.self) {
                    accepted = true
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in
                            IncomingTorrentFiles.handle([url])
                        }
                    }
                }
                return accepted
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

@MainActor
enum IncomingTorrentFiles {
    static let didReceive = Notification.Name("TorrentPlayer.openTorrentFiles")
    private static var queued: [URL] = []

    static func isTorrentFileURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "torrent"
    }

    static func handle(_ urls: [URL]) {
        let torrents = urls.filter(isTorrentFileURL).filter { url in
            !queued.contains(url)
        }
        guard !torrents.isEmpty else { return }
        queued.append(contentsOf: torrents)
        NotificationCenter.default.post(name: didReceive, object: nil)
    }

    static func take() -> [URL] {
        let urls = queued
        queued.removeAll()
        return urls
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

    /// Dock / Finder drop onto the app icon. SwiftUI `onOpenURL` often misses this
    /// when an `NSApplicationDelegateAdaptor` is present.
    func application(_ application: NSApplication, open urls: [URL]) {
        IncomingTorrentFiles.handle(urls)
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
