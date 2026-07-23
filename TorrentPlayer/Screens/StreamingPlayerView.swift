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
import AppKit
import QuartzCore
#else
import UIKit
#endif
#endif

struct StreamingPlayerView: View {
    /// When false (another tab is visible), playback pauses but the player stays mounted.
    var isActive: Bool = true
    /// Shared with the root shell so iOS can hide nav/header without remounting the video surface.
    @Binding var isFullscreen: Bool

    @Environment(TorrentEngine.self) private var engine
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var bufferedFraction: Double = 0
    @State private var volume: Float = 1.0
    @State private var controlsVisible = true
    @State private var controlsHideToken = UUID()
    @State private var audioTrackOptions: [AudioTrackOption] = []
    @State private var showAudioTrackMenu = false
    #if os(macOS) || os(iOS)
    @State private var player: AVPlayer?
    @State private var vlcPlayer: Player?
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?
    @State private var statusObservation: NSKeyValueObservation?
    @State private var avAudibleGroup: AVMediaSelectionGroup?
    /// Bumped after macOS window fullscreen so AV/VLC surfaces re-attach.
    @State private var videoAttachID = 0
    #endif
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(isActive: Bool = true, isFullscreen: Binding<Bool> = .constant(false)) {
        self.isActive = isActive
        self._isFullscreen = isFullscreen
    }

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
        let speed = PlaybackFormatting.formatRate(engine.downloadRateBytes)
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
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: KTSpacing.md) {
                    if !isFullscreen {
                        Text(titleText)
                            .font(KTTypography.headlineLGMobile())
                            .foregroundStyle(KTColor.onSecondary)
                            .italic()
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(KTSpacing.sm)
                            .background(KTColor.secondaryContainer)
                            .thickBorder()
                            .hardShadow()
                    }

                    playerCanvas
                        // Keep one video surface: expand the same canvas instead of
                        // fullScreenCover (that remounted AV/VLC and ate touch events).
                        .aspectRatio(isFullscreen ? nil : 16 / 9, contentMode: .fit)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: isFullscreen ? geo.size.height : nil,
                            maxHeight: isFullscreen ? geo.size.height : nil
                        )
                        .thickBorder(isFullscreen ? .clear : KTColor.onBackground)

                    if !isFullscreen {
                        progressSection(overlayOnVideo: false)
                        statsGrid
                        streamInfoCard
                    }
                }
                .padding(isFullscreen ? 0 : KTSpacing.md)
                .frame(maxWidth: isFullscreen ? .infinity : 960, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .scrollDisabled(isFullscreen)
            .background(isFullscreen ? Color.black : KTColor.background)
        }
        #if os(iOS)
        .statusBarHidden(isFullscreen)
        .persistentSystemOverlays(isFullscreen ? .hidden : .automatic)
        #endif
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            reattachVideoAfterWindowFullscreen(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            reattachVideoAfterWindowFullscreen(note)
        }
        #endif
        #if os(macOS) || os(iOS)
        .task(id: engine.selectedFileID) {
            guard isActive, engine.selectedFileID != nil else { return }
            // Keep a live stream across tab switches; only prepare when none exists yet.
            if engine.playbackURL != nil { return }
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
            if active {
                if engine.selectedFileID != nil, engine.playbackURL == nil {
                    Task { await engine.preparePlayback() }
                }
            } else {
                pausePlayback()
                isFullscreen = false
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                scheduleControlsAutoHide()
            } else {
                showControls(animated: true)
            }
        }
        .task(id: controlsHideToken) {
            await runControlsAutoHide()
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if os(macOS) || os(iOS)
            if hasActivePlayer {
                videoSurface
                    .id(videoAttachID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // UIViewRepresentable hosts often win hit-testing over SwiftUI controls.
                    .allowsHitTesting(false)
            } else {
                playbackPlaceholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #else
            playbackPlaceholder
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif

            // Tap target under chrome — toggles / reveals controls without shifting layout.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    handleCanvasTap()
                }

            // Keep chrome in the hierarchy (opacity only). Removing the VStack+Spacer
            // collapses the ZStack to the video's intrinsic size and shrinks playback.
            VStack {
                HStack {
                    Text(liveBadgeText)
                        .font(KTTypography.technicalSM())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                    Spacer()
                    // Top-right: stays visible on narrow phones where the bottom
                    // transport row clips the fullscreen control past the volume bar.
                    controlButton(
                        systemImage: isFullscreen ? "xmark" : fullscreenButtonImage,
                        fill: .white,
                        tint: KTColor.onBackground
                    ) {
                        userInteractedWithControls()
                        toggleFullscreen()
                    }
                }
                .padding(KTSpacing.sm)

                Spacer(minLength: 0)

                if showAudioTrackMenu, AudioTrackSelection.shouldShowPicker(trackCount: audioTrackOptions.count) {
                    audioTrackMenu
                        .padding(.horizontal, KTSpacing.md)
                        .padding(.bottom, KTSpacing.xs)
                }

                HStack(spacing: KTSpacing.sm) {
                    controlButton(
                        systemImage: isPlaying ? "pause.fill" : "play.fill",
                        fill: KTColor.primaryContainer,
                        tint: KTColor.onPrimaryContainer
                    ) {
                        userInteractedWithControls()
                        togglePlayPause()
                    }
                    controlButton(systemImage: "backward.fill", fill: .white, tint: KTColor.onBackground) {
                        userInteractedWithControls()
                        skip(by: -10)
                    }
                    controlButton(systemImage: "forward.fill", fill: .white, tint: KTColor.onBackground) {
                        userInteractedWithControls()
                        skip(by: 10)
                    }
                    Spacer(minLength: KTSpacing.xs)
                    if AudioTrackSelection.shouldShowPicker(trackCount: audioTrackOptions.count) {
                        controlButton(
                            systemImage: "waveform",
                            fill: showAudioTrackMenu ? KTColor.tertiaryContainer : .white,
                            tint: KTColor.onBackground
                        ) {
                            toggleAudioTrackMenu()
                        }
                    }
                    volumeControl
                }
                .padding(.horizontal, KTSpacing.md)
                .padding(.top, KTSpacing.md)
                .padding(.bottom, isFullscreen ? KTSpacing.sm : KTSpacing.md)

                if isFullscreen {
                    progressSection(overlayOnVideo: true)
                        .padding(.horizontal, KTSpacing.md)
                        .padding(.bottom, KTSpacing.md)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
    }

    private var volumeControl: some View {
        HStack(spacing: KTSpacing.xs) {
            Text("VOL")
                .font(KTTypography.technicalSM())
            GeometryReader { geo in
                let fillWidth = max(0, min(geo.size.width, CGFloat(volume) * geo.size.width))
                ZStack(alignment: .leading) {
                    Rectangle().fill(KTColor.surfaceContainer)
                    Rectangle()
                        .fill(KTColor.tertiary)
                        .frame(width: fillWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(Rectangle().strokeBorder(KTColor.onBackground, lineWidth: 1))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let next = Float(value.location.x / max(geo.size.width, 1))
                            volume = min(1, max(0, next))
                            applyVolume()
                            userInteractedWithControls()
                        }
                )
            }
            .frame(width: volumeBarWidth, height: 14)
        }
        .padding(.horizontal, KTSpacing.sm)
        .padding(.vertical, KTSpacing.xs)
        .background(.white)
        .thickBorder()
    }

    private var volumeBarWidth: CGFloat {
        #if os(iOS)
        sizeClass == .compact ? 56 : 96
        #else
        96
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

    @ViewBuilder
    private var videoSurface: some View {
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
                .onChange(of: vlcPlayer.audioTracks) { _, _ in
                    refreshVLCAudioTracks()
                }
                .onChange(of: vlcPlayer.selectedAudioTrack?.id) { _, _ in
                    refreshVLCAudioTracks()
                }
        }
    }

    #endif

    private var audioTrackMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AUDIO_TRACK")
                .font(KTTypography.labelCaps())
                .foregroundStyle(KTColor.onSurfaceVariant)
                .tracking(1.1)
                .padding(.horizontal, KTSpacing.sm)
                .padding(.vertical, KTSpacing.xs)

            ForEach(audioTrackOptions) { option in
                Button {
                    selectAudioTrack(id: option.id)
                    showAudioTrackMenu = false
                    userInteractedWithControls()
                } label: {
                    HStack(spacing: KTSpacing.sm) {
                        Text(option.label.uppercased(with: .current))
                            .font(KTTypography.technicalSM().weight(.bold))
                            .foregroundStyle(KTColor.onBackground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: KTSpacing.xs)
                        if option.isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(KTColor.primary)
                        }
                    }
                    .padding(.horizontal, KTSpacing.sm)
                    .padding(.vertical, KTSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(option.isSelected ? KTColor.tertiaryContainer : Color.white)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .background(Color.white)
        .thickBorder()
        .hardShadow()
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

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

    private func progressSection(overlayOnVideo: Bool) -> some View {
        VStack(alignment: .leading, spacing: KTSpacing.xs) {
            HStack {
                Text(PlaybackFormatting.clock(seconds: duration > 0 ? currentTime : nil))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: KTSpacing.xs)
                Text(PlaybackFormatting.clock(seconds: duration > 0 ? duration : nil))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .font(KTTypography.technicalMD().weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(overlayOnVideo ? Color.white : KTColor.onBackground)
            .frame(maxWidth: .infinity)

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
                                // Keep playhead inside the bar horizontally; only lift vertically.
                                Rectangle()
                                    .fill(KTColor.primary)
                                    .frame(width: 6, height: 40)
                                    .overlay(Rectangle().strokeBorder(KTColor.onBackground, lineWidth: 2))
                                    .offset(y: -4)
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .thickBorder()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            userInteractedWithControls()
                        }
                        .onEnded { value in
                            guard duration > 0, geo.size.width > 0 else { return }
                            let fraction = min(1, max(0, value.location.x / geo.size.width))
                            seek(to: duration * Double(fraction))
                            userInteractedWithControls()
                        }
                )
            }
            .frame(height: 32)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
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

    private var fullscreenButtonImage: String {
        isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
    }

    private func applyVolume() {
        #if os(macOS) || os(iOS)
        player?.volume = volume
        if let vlcPlayer {
            try? vlcPlayer.setAudioVolume(Volume(volume))
        }
        #endif
    }

    private func toggleFullscreen() {
        // In-app expand of the player canvas (same surface). Do not use
        // NSWindow.toggleFullScreen — that fullscreen the whole app chrome.
        isFullscreen.toggle()
        showControls(animated: true)
        scheduleControlsAutoHide()
    }

    private func handleCanvasTap() {
        if showAudioTrackMenu {
            showAudioTrackMenu = false
            userInteractedWithControls()
            return
        }
        if controlsVisible {
            withAnimation(.easeInOut(duration: 0.25)) {
                controlsVisible = false
            }
            controlsHideToken = UUID()
        } else {
            showControls(animated: true)
            scheduleControlsAutoHide()
        }
    }

    private func toggleAudioTrackMenu() {
        if showAudioTrackMenu {
            showAudioTrackMenu = false
            userInteractedWithControls()
        } else {
            // Set flag before showing controls so auto-hide is skipped while open.
            showAudioTrackMenu = true
            showControls(animated: false)
        }
    }

    private func selectAudioTrack(id: String) {
        #if os(macOS) || os(iOS)
        if let vlcPlayer, engine.usesEmbeddedVLC {
            guard let track = vlcPlayer.audioTracks.first(where: { $0.id == id }) else { return }
            vlcPlayer.selectedAudioTrack = track
            refreshVLCAudioTracks()
            return
        }
        guard let item = player?.currentItem,
              let group = avAudibleGroup,
              let option = group.options.enumerated().first(where: {
                  Self.avTrackID(for: $0.element, index: $0.offset) == id
              })?.element
        else { return }
        item.select(option, in: group)
        refreshAVAudioTracks()
        #endif
    }

    #if os(macOS) || os(iOS)
    private func refreshVLCAudioTracks() {
        guard let vlcPlayer else {
            audioTrackOptions = []
            return
        }
        audioTrackOptions = vlcPlayer.audioTracks.enumerated().map { index, track in
            AudioTrackOption(
                id: track.id,
                label: AudioTrackSelection.label(
                    name: track.name,
                    language: track.language,
                    description: track.trackDescription,
                    fallbackIndex: index + 1
                ),
                isSelected: track.isSelected
            )
        }
        if !AudioTrackSelection.shouldShowPicker(trackCount: audioTrackOptions.count) {
            showAudioTrackMenu = false
        }
    }

    private func refreshAVAudioTracks() {
        guard let item = player?.currentItem, let group = avAudibleGroup else {
            audioTrackOptions = []
            return
        }
        let selected = item.currentMediaSelection.selectedMediaOption(in: group)
        audioTrackOptions = group.options.enumerated().map { index, option in
            AudioTrackOption(
                id: Self.avTrackID(for: option, index: index),
                label: AudioTrackSelection.label(
                    name: option.displayName,
                    language: Self.avLanguageTag(for: option),
                    fallbackIndex: index + 1
                ),
                isSelected: option == selected
            )
        }
        if !AudioTrackSelection.shouldShowPicker(trackCount: audioTrackOptions.count) {
            showAudioTrackMenu = false
        }
    }

    private func loadAVAudioTracks(for player: AVPlayer) async {
        guard let item = player.currentItem else { return }
        do {
            let group = try await item.asset.loadMediaSelectionGroup(for: .audible)
            await MainActor.run {
                guard self.player === player else { return }
                avAudibleGroup = group
                refreshAVAudioTracks()
            }
        } catch {
            TPLog.error("AV audible tracks load failed: \(error.localizedDescription)")
            await MainActor.run {
                guard self.player === player else { return }
                avAudibleGroup = nil
                audioTrackOptions = []
                showAudioTrackMenu = false
            }
        }
    }

    /// Stable enough across re-probes: language + display name, with index as a disambiguator.
    private static func avTrackID(for option: AVMediaSelectionOption, index: Int) -> String {
        let lang = avLanguageTag(for: option) ?? ""
        return "av:\(index):\(lang):\(option.displayName)"
    }

    private static func avLanguageTag(for option: AVMediaSelectionOption) -> String? {
        option.extendedLanguageTag ?? option.locale?.language.languageCode?.identifier
    }
    #endif

    private func userInteractedWithControls() {
        showControls(animated: false)
        scheduleControlsAutoHide()
    }

    private func showControls(animated: Bool) {
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                controlsVisible = true
            }
        } else {
            controlsVisible = true
        }
    }

    private func scheduleControlsAutoHide() {
        guard isPlaying, !showAudioTrackMenu else { return }
        controlsHideToken = UUID()
    }

    private func runControlsAutoHide() async {
        guard controlsVisible, isPlaying, !showAudioTrackMenu else { return }
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled, controlsVisible, isPlaying, !showAudioTrackMenu else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            controlsVisible = false
        }
    }

    #if os(macOS)
    private func reattachVideoAfterWindowFullscreen(_ note: Notification) {
        guard isActive, hasActivePlayer else { return }
        guard (note.object as? NSWindow) === NSApp.keyWindow else { return }
        // VLC drawable and AVPlayerLayer both need a fresh host after Space switch.
        DispatchQueue.main.async {
            videoAttachID += 1
        }
    }
    #endif

    private func togglePlayPause() {
        #if os(macOS) || os(iOS)
        if let vlcPlayer, engine.usesEmbeddedVLC {
            if vlcPlayer.isMuted {
                vlcPlayer.isMuted = false
            }
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
                // Mute before play so inactive rebuild (play→pause) cannot emit a short blip.
                if !isActive {
                    next.isMuted = true
                }
                try next.play(url: url)
                try? next.setAudioVolume(Volume(volume))
                if isActive {
                    isPlaying = true
                } else {
                    next.pause()
                    isPlaying = false
                }
                refreshVLCAudioTracks()
            } catch {
                TPLog.error("SwiftVLC play failed: \(error.localizedDescription)")
                isPlaying = false
            }
            return
        }

        let next = AVPlayer(url: url)
        next.volume = volume
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

        statusObservation?.invalidate()
        statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak player] item, _ in
            guard item.status == .readyToPlay, let player else { return }
            Task { @MainActor in
                await loadAVAudioTracks(for: player)
            }
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
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        player = nil
        vlcPlayer?.stop()
        vlcPlayer = nil
        avAudibleGroup = nil
        audioTrackOptions = []
        showAudioTrackMenu = false
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
/// AVPlayerLayer host — AVPlayerView often goes black (audio OK) after
/// `NSWindow.toggleFullScreen` when embedded via SwiftUI representable.
private struct BareVideoView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerNSView {
        let view = PlayerLayerNSView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerNSView, context: Context) {
        nsView.player = player
    }
}

private final class PlayerLayerNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var fullscreenObservers: [NSObjectProtocol] = []

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspect
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerAddsPlayer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeFullscreenObservers()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeFullscreenObservers()
        guard let window else { return }
        let refresh: (Notification) -> Void = { [weak self] _ in
            // Bounds are often still stale in the notification callback.
            DispatchQueue.main.async {
                self?.refreshVideoSurface()
            }
        }
        let center = NotificationCenter.default
        fullscreenObservers = [
            center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main, using: refresh),
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main, using: refresh),
        ]
        refreshVideoSurface()
    }

    private func layerAddsPlayer() {
        guard let host = layer else { return }
        playerLayer.videoGravity = .resizeAspect
        if playerLayer.superlayer !== host {
            host.addSublayer(playerLayer)
        }
        playerLayer.frame = bounds
    }

    private func refreshVideoSurface() {
        layerAddsPlayer()
        // Re-bind so the compositor picks up the layer after Space / fullscreen changes.
        guard let current = playerLayer.player else { return }
        playerLayer.player = nil
        playerLayer.player = current
    }

    private func removeFullscreenObservers() {
        let center = NotificationCenter.default
        for observer in fullscreenObservers {
            center.removeObserver(observer)
        }
        fullscreenObservers.removeAll()
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
    private var pendingPlayer: AVPlayer?

    var player: AVPlayer? {
        get { playerLayer.player ?? pendingPlayer }
        set {
            pendingPlayer = newValue
            attachPlayerIfReady()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        attachPlayerIfReady()
    }

    private func attachPlayerIfReady() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        playerLayer.videoGravity = .resizeAspect
        if playerLayer.player !== pendingPlayer {
            playerLayer.player = pendingPlayer
        }
    }
}
#endif

#Preview {
    StreamingPlayerView()
        .environment(TorrentEngine())
}
