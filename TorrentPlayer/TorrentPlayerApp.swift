//
//  TorrentPlayerApp.swift
//  TorrentPlayer
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import CoreTransferable
#endif
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
        #if os(macOS)
        // Single window: Dock/Finder opens of .torrent files reuse it instead of
        // spawning another window (and another player on the shared engine).
        Window("TorrentPlayer", id: "main") {
            rootView
        }
        .modelContainer(for: TorrentHistoryEntry.self)
        #else
        WindowGroup {
            rootView
        }
        .modelContainer(for: TorrentHistoryEntry.self)
        #endif
    }

    private var rootView: some View {
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
        #if os(iOS)
        .dropDestination(for: TorrentFileDrop.self) { items, _ in
            IncomingTorrentFiles.handle(items.map(\.url))
            return !items.isEmpty
        }
        #else
        .dropDestination(for: URL.self) { urls, _ in
            IncomingTorrentFiles.handle(urls)
            return urls.contains(where: IncomingTorrentFiles.isTorrentFileURL)
        }
        #endif
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
}

@MainActor
enum IncomingTorrentFiles {
    static let didReceive = Notification.Name("TorrentPlayer.openTorrentFiles")
    nonisolated static let contentType = UTType(importedAs: "org.bittorrent.torrent")

    private static var queued: [URL] = []
    private static var isConsuming = false

    static var hasPending: Bool { !queued.isEmpty }

    nonisolated static func isTorrentFileURL(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.lowercased() == "torrent"
    }

    /// Keeps only the last .torrent file. Multiple drops/opens replace the previous pending URL.
    static func handle(_ urls: [URL]) {
        guard enqueueLatest(urls) else { return }
        NotificationCenter.default.post(name: didReceive, object: nil)
    }

    @discardableResult
    static func enqueueLatest(_ urls: [URL]) -> Bool {
        guard let latest = urls.last(where: isTorrentFileURL) else { return false }
        if let previous = queued.last, previous != latest {
            removeConsumedCopyIfNeeded(previous)
        }
        queued = [latest]
        return true
    }

    static func takeLatest() -> URL? {
        let url = queued.last
        queued.removeAll()
        return url
    }

    static func discardLatest() {
        guard let url = takeLatest() else { return }
        removeConsumedCopyIfNeeded(url)
    }

    static func consumeExclusively(_ body: () async -> Void) async {
        guard !isConsuming else { return }
        isConsuming = true
        defer { isConsuming = false }
        await body()
    }

    /// Copies a dropped file to a location the app can read after the drop callback returns.
    nonisolated static func persistDroppedFile(_ url: URL) throws -> URL {
        let dir = incomingDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("\(UUID().uuidString).torrent")
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    /// Deletes Inbox copies from "Open in…" and our drop staging copies. Leaves the user's original file alone.
    nonisolated static func removeConsumedCopyIfNeeded(_ url: URL) {
        guard url.isFileURL else { return }
        let fm = FileManager.default
        if isStrictlyInside(url, directory: incomingDirectory) {
            try? fm.removeItem(at: url)
            return
        }
        #if os(iOS)
        guard let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true)
        if isStrictlyInside(url, directory: inbox) {
            try? fm.removeItem(at: url)
        }
        #endif
    }

    nonisolated private static var incomingDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TorrentPlayerIncoming", isDirectory: true)
    }

    nonisolated private static func isStrictlyInside(_ url: URL, directory: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        let dirPath = directory.resolvingSymlinksInPath().path
        return path.hasPrefix(dirPath.hasSuffix("/") ? dirPath : dirPath + "/")
    }
}

#if os(iOS)
/// FileRepresentation copies the dropped file into the sandbox.
private struct TorrentFileDrop: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(
            importedContentType: IncomingTorrentFiles.contentType,
            shouldAttemptToOpenInPlace: false
        ) { received in
            TorrentFileDrop(url: try IncomingTorrentFiles.persistDroppedFile(received.file))
        }
    }
}
#endif

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
