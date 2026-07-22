//
//  StreamingPlayerView.swift
//  TorrentPlayer
//
//  design/streaming_player/ — Task #7 stream bridge; Task #8 play/pause + dual progress;
//  Task #15 / #22 embedded SwiftVLC; Task #11 iOS playback.
//

import SwiftUI
#if os(macOS) || os(iOS)
import AVFoundation
import SwiftVLC
#if os(macOS)
import AVKit
#else
import UIKit
#endif
#endif

struct StreamingPlayerView: View {
    /// When false (another tab is visible), playback pauses but the player stays mounted.
    var isActive: Bool = true

    @Environment(TorrentEngine.self) private var engine
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var bufferedFraction: Double = 0
    #if os(macOS) || os(iOS)
    @State private var player: AVPlayer?
    @State private var vlcPlayer: Player?
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?
    #endif
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var statsColumnCount: Int {
        #if os(macOS)
        4
        #else
        sizeClass == .compact ? 1 : 4
        #endif
    }

    private var downloadBarFraction: Double {
        max(
            PlaybackFormatting.downloadFraction(engine.downloadProgress),
            PlaybackFormatting.downloadFraction(bufferedFraction)
        )
    }

    private var playbackBarFraction: Double {
        PlaybackFormatting.fraction(current: currentTime, duration: duration)
    }

    private var stats: [(label: String, value: String, color: Color)] {
        let speed = formatRate(engine.downloadRateBytes)
        let peers = engine.peersConnected > 0 ? "\(engine.peersConnected)" : "—"
        let eta = PlaybackFormatting.etaClock(
            progress: engine.downloadProgress,
            rateBytesPerSecond: engine.downloadRateBytes,
            totalBytes: engine.selectedFile?.size ?? 0
        )
        let protocolLabel = engine.usesEmbeddedVLC ? "SWIFT_VLC" : "LOCAL_HTTP"
        return [
            ("DL_SPEED", speed, KTColor.primary),
            ("PEERS_CONNECTED", peers, KTColor.secondary),
            ("ETA_REMAINING", eta, KTColor.onBackground),
            ("PROTOCOL", protocolLabel, KTColor.tertiary),
        ]
    }

    private var titleText: String {
        engine.selectedFile?.name ?? "NO_VIDEO_SELECTED"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KTSpacing.md) {
                Text(titleText)
                    .font(KTTypography.headlineLGMobile())
                    .foregroundStyle(KTColor.onSecondary)
                    .italic()
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .padding(KTSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KTColor.secondaryContainer)
                    .thickBorder()
                    .hardShadow()

                playerCanvas
                progressSection
                statsGrid
                streamInfoCard
            }
            .padding(KTSpacing.md)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(KTColor.background)
        #if os(macOS) || os(iOS)
        .task(id: engine.selectedFileID) {
            guard engine.selectedFileID != nil else { return }
            await engine.preparePlayback()
        }
        .task(id: engine.playbackPhase) {
            while !Task.isCancelled {
                await engine.refreshDownloadStatus()
                try? await Task.sleep(for: .seconds(1))
                if engine.playbackPhase == .idle { break }
            }
        }
        .onChange(of: engine.playbackURL) { _, url in
            rebuildPlayer(with: url)
        }
        .onChange(of: isActive) { _, active in
            if !active {
                pausePlayback()
            }
        }
        #endif
    }

    private var playerCanvas: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0A1628), Color(hex: 0x1A0A14), KTColor.primary.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            #if os(macOS) || os(iOS)
            if let player, !engine.usesEmbeddedVLC {
                BareVideoView(player: player)
            } else if let vlcPlayer, engine.usesEmbeddedVLC {
                VideoView(vlcPlayer)
                    .onChange(of: vlcPlayer.currentTime) { _, time in
                        currentTime = Self.seconds(from: time)
                    }
                    .onChange(of: vlcPlayer.duration) { _, mediaDuration in
                        if let mediaDuration {
                            duration = Self.seconds(from: mediaDuration)
                        }
                    }
                    .onChange(of: vlcPlayer.bufferFill) { _, fill in
                        bufferedFraction = Double(fill)
                    }
                    .onChange(of: vlcPlayer.isPlaybackRequestedActive) { _, active in
                        isPlaying = active
                    }
                    .onChange(of: vlcPlayer.state) { _, state in
                        if case .stopped = state, vlcPlayer.didReachEnd {
                            isPlaying = false
                        }
                    }
            } else {
                playbackPlaceholder
            }
            #else
            playbackPlaceholder
            #endif

            VStack {
                HStack {
                    Text(liveBadgeText)
                        .font(KTTypography.technicalSM())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                    Spacer()
                }
                .padding(KTSpacing.sm)

                Spacer()

                if showsCenterPlayOverlay {
                    Button(action: togglePlayPause) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(KTColor.onPrimary)
                            .frame(width: 96, height: 96)
                            .background(KTColor.primary)
                            .thickBorder()
                            .hardShadow()
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                HStack(spacing: KTSpacing.sm) {
                    controlButton(
                        systemImage: isPlaying ? "pause.fill" : "play.fill",
                        fill: KTColor.primaryContainer,
                        tint: KTColor.onPrimaryContainer
                    ) {
                        togglePlayPause()
                    }
                    controlButton(systemImage: "backward.fill", fill: .white, tint: KTColor.onBackground) {
                        skip(by: -10)
                    }
                    controlButton(systemImage: "forward.fill", fill: .white, tint: KTColor.onBackground) {
                        skip(by: 10)
                    }
                    Spacer()
                    HStack(spacing: KTSpacing.xs) {
                        Text("VOL")
                            .font(KTTypography.technicalSM())
                        ZStack(alignment: .leading) {
                            Rectangle().fill(KTColor.surfaceContainer)
                            Rectangle()
                                .fill(KTColor.tertiary)
                                .frame(width: 72)
                        }
                        .frame(width: 96, height: 14)
                        .overlay(Rectangle().strokeBorder(KTColor.onBackground, lineWidth: 1))
                    }
                    .padding(.horizontal, KTSpacing.sm)
                    .padding(.vertical, KTSpacing.xs)
                    .background(.white)
                    .thickBorder()
                }
                .padding(KTSpacing.md)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .thickBorder()
    }

    private var showsCenterPlayOverlay: Bool {
        #if os(macOS) || os(iOS)
        hasActivePlayer && !isPlaying && engine.playbackPhase == .ready
        #else
        false
        #endif
    }

    #if os(macOS) || os(iOS)
    private var hasActivePlayer: Bool {
        if engine.usesEmbeddedVLC {
            vlcPlayer != nil
        } else {
            player != nil
        }
    }
    #endif

    private var playbackPlaceholder: some View {
        VStack(spacing: KTSpacing.sm) {
            Image(systemName: placeholderIcon)
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.85))
            Text(placeholderLabel)
                .font(KTTypography.technicalSM())
                .foregroundStyle(.white.opacity(0.7))
                .tracking(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, KTSpacing.md)
        }
    }

    private var liveBadgeText: String {
        switch engine.playbackPhase {
        case .ready:
            isPlaying ? "● LIVE" : "● PAUSED"
        case .buffering:
            "● BUFFERING"
        case .failed:
            "● ERROR"
        case .idle:
            "● IDLE"
        }
    }

    private var placeholderIcon: String {
        switch engine.playbackPhase {
        case .failed:
            "exclamationmark.triangle.fill"
        case .buffering:
            "arrow.down.circle"
        default:
            "play.rectangle.fill"
        }
    }

    private var placeholderLabel: String {
        switch engine.playbackPhase {
        case let .failed(message):
            return message.uppercased()
        case .buffering:
            let pct = Int(engine.downloadProgress * 100)
            return "BUFFERING \(pct)% • \(engine.piecesCompleted) PIECES"
        case .idle:
            return "WAITING FOR STREAM"
        case .ready:
            return "STARTING…"
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: KTSpacing.xs) {
            HStack {
                Text(PlaybackFormatting.clock(seconds: duration > 0 ? currentTime : nil))
                Spacer()
                Text(PlaybackFormatting.clock(seconds: duration > 0 ? duration : nil))
            }
            .font(KTTypography.technicalMD().weight(.bold))
            .textCase(.uppercase)

            GeometryReader { geo in
                let downloadWidth = geo.size.width * downloadBarFraction
                let playbackWidth = geo.size.width * playbackBarFraction
                ZStack(alignment: .leading) {
                    KTColor.surfaceContainer
                    HazardStripes()
                        .frame(width: max(0, downloadWidth))
                        .clipped()
                    KTColor.tertiaryContainer
                        .frame(width: max(0, playbackWidth))
                        .overlay(alignment: .trailing) {
                            if playbackBarFraction > 0 {
                                Rectangle()
                                    .fill(KTColor.primary)
                                    .frame(width: 6, height: 40)
                                    .overlay(Rectangle().strokeBorder(KTColor.onBackground, lineWidth: 2))
                                    .offset(x: 3, y: -4)
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .thickBorder()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            guard duration > 0, geo.size.width > 0 else { return }
                            let fraction = min(1, max(0, value.location.x / geo.size.width))
                            seek(to: duration * Double(fraction))
                        }
                )
            }
            .frame(height: 32)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 0),
                count: statsColumnCount
            ),
            spacing: 0
        ) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                statCell(label: stat.label, value: stat.value, valueColor: stat.color)
            }
        }
        .thickBorder()
    }

    private var streamInfoCard: some View {
        VStack(alignment: .leading, spacing: KTSpacing.sm) {
            HStack(spacing: KTSpacing.xs) {
                Image(systemName: "info.circle")
                    .foregroundStyle(KTColor.primary)
                Text("STREAM_INFO")
                    .font(KTTypography.headlineLGMobile())
                    .italic()
                    .textCase(.uppercase)
            }
            Text(streamInfoText)
            .font(KTTypography.technicalSM())
            .foregroundStyle(KTColor.onSurfaceVariant)
        }
        .padding(KTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KTColor.surface)
        .thickBorder()
        .hardShadow()
    }

    private var streamInfoText: String {
        let path = engine.selectedFile?.path ?? "—"
        let url = engine.playbackURL?.absoluteString ?? "—"
        let playerKind = engine.usesEmbeddedVLC ? "EMBEDDED_VLC" : "AVPLAYER"
        let dl = Int(PlaybackFormatting.downloadFraction(engine.downloadProgress) * 100)
        return """
        FILE: \(path)
        SOURCE: LOCAL_HTTP_LOOPBACK
        PLAYER: \(playerKind)
        DOWNLOAD: \(dl)%
        PLAYBACK_URL: \(url)
        """
    }

    private func formatRate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    private func togglePlayPause() {
        #if os(macOS) || os(iOS)
        if let vlcPlayer, engine.usesEmbeddedVLC {
            vlcPlayer.togglePlayPause()
            isPlaying = vlcPlayer.isPlaybackRequestedActive
            return
        }
        guard let player else {
            isPlaying.toggle()
            return
        }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        #else
        isPlaying.toggle()
        #endif
    }

    /// Pauses without tearing down AVPlayer / VLC or the HTTP stream bridge.
    private func pausePlayback() {
        #if os(macOS) || os(iOS)
        if let vlcPlayer, engine.usesEmbeddedVLC {
            vlcPlayer.pause()
            isPlaying = false
            return
        }
        player?.pause()
        isPlaying = false
        #endif
    }

    private func skip(by delta: TimeInterval) {
        guard duration > 0 else { return }
        seek(to: currentTime + delta)
    }

    private func seek(to seconds: TimeInterval) {
        #if os(macOS) || os(iOS)
        let target = min(duration, max(0, seconds))
        if let vlcPlayer, engine.usesEmbeddedVLC {
            guard duration > 0 else { return }
            let millis = Int64((target * 1000).rounded())
            try? vlcPlayer.seek(to: .milliseconds(millis), fast: true)
            currentTime = target
            return
        }
        guard let player, duration > 0 else { return }
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
        #endif
    }

    #if os(macOS) || os(iOS)
    private func rebuildPlayer(with url: URL?) {
        tearDownPlayer()
        guard let url else { return }
        activatePlaybackAudioSessionIfNeeded()

        if engine.usesEmbeddedVLC {
            let next = Player()
            vlcPlayer = next
            do {
                try next.play(url: url)
                if isActive {
                    isPlaying = true
                } else {
                    next.pause()
                    isPlaying = false
                }
            } catch {
                TPLog.error("SwiftVLC play failed: \(error.localizedDescription)")
                isPlaying = false
            }
            return
        }

        let next = AVPlayer(url: url)
        player = next
        attachObservers(to: next)
        if isActive {
            next.play()
            isPlaying = true
        } else {
            isPlaying = false
        }
    }

    private func activatePlaybackAudioSessionIfNeeded() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            TPLog.error("AVAudioSession activate failed: \(error.localizedDescription)")
        }
        #endif
    }

    private func attachObservers(to player: AVPlayer) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player else { return }
            let seconds = time.seconds
            if seconds.isFinite {
                currentTime = max(0, seconds)
            }
            if let item = player.currentItem {
                let itemDuration = item.duration.seconds
                let resolvedDuration: TimeInterval
                if itemDuration.isFinite, itemDuration > 0 {
                    duration = itemDuration
                    resolvedDuration = itemDuration
                } else {
                    resolvedDuration = duration
                }
                bufferedFraction = Self.loadedFraction(for: item, duration: resolvedDuration)
            }
            isPlaying = player.timeControlStatus == .playing
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            isPlaying = false
        }
    }

    private func tearDownPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
        vlcPlayer?.stop()
        vlcPlayer = nil
        currentTime = 0
        duration = 0
        bufferedFraction = 0
        isPlaying = false
    }

    private static func loadedFraction(for item: AVPlayerItem, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        guard let range = item.loadedTimeRanges.first?.timeRangeValue else { return 0 }
        let end = range.start.seconds + range.duration.seconds
        guard end.isFinite else { return 0 }
        return PlaybackFormatting.fraction(current: end, duration: duration)
    }

    private static func seconds(from duration: Duration) -> TimeInterval {
        Double(duration.milliseconds) / 1000.0
    }
    #endif

    private func statCell(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: KTSpacing.xs) {
            Text(label)
                .font(KTTypography.labelCaps())
                .foregroundStyle(KTColor.onSurfaceVariant)
                .tracking(1.1)
            Text(value)
                .font(KTTypography.technicalMD().weight(.bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(KTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .overlay {
            Rectangle().strokeBorder(KTColor.onBackground, lineWidth: KTSpacing.borderThick)
        }
    }

    private func controlButton(
        systemImage: String,
        fill: Color,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(fill)
                .thickBorder()
                .hardShadow()
        }
        .buttonStyle(.plain)
    }
}

#if os(macOS)
/// AVPlayer surface without system chrome so Kinetic controls stay visible.
private struct BareVideoView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
#elseif os(iOS)
/// AVPlayer surface without system chrome so Kinetic controls stay visible.
private struct BareVideoView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.player = player
    }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspect
        }
    }
}
#endif

#Preview {
    StreamingPlayerView()
        .environment(TorrentEngine())
}
