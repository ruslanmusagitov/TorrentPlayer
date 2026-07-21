//
//  StreamingPlayerView.swift
//  TorrentPlayer
//
//  design/streaming_player/ — Task #7: AVPlayer over local HTTP stream.
//

import SwiftUI
#if os(macOS)
import AVKit
#endif

struct StreamingPlayerView: View {
    @Environment(TorrentEngine.self) private var engine
    @State private var isPlaying = true
    #if os(macOS)
    @State private var player: AVPlayer?
    #endif
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var statsColumnCount: Int {
        #if os(macOS)
        4
        #else
        sizeClass == .compact ? 1 : 4
        #endif
    }

    private var stats: [(label: String, value: String, color: Color)] {
        [
            ("DL_SPEED", "—", KTColor.primary),
            ("PEERS_CONNECTED", "—", KTColor.secondary),
            ("ETA_REMAINING", "—", KTColor.onBackground),
            ("PROTOCOL", "LOCAL_HTTP", KTColor.tertiary),
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
        #if os(macOS)
        .task(id: engine.selectedFileID) {
            await engine.preparePlayback()
        }
        .onChange(of: engine.playbackURL) { _, url in
            rebuildPlayer(with: url)
        }
        .onDisappear {
            player?.pause()
            player = nil
            engine.stopPlayback()
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

            #if os(macOS)
            if let player {
                VideoPlayer(player: player)
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
                HStack(spacing: KTSpacing.sm) {
                    controlButton(
                        systemImage: isPlaying ? "pause.fill" : "play.fill",
                        fill: KTColor.primaryContainer,
                        tint: KTColor.onPrimaryContainer
                    ) {
                        togglePlayPause()
                    }
                    controlButton(systemImage: "backward.fill", fill: .white, tint: KTColor.onBackground) {}
                    controlButton(systemImage: "forward.fill", fill: .white, tint: KTColor.onBackground) {}
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
            "● LIVE"
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
            message.uppercased()
        case .buffering:
            "BUFFERING STREAM…"
        case .idle:
            "WAITING FOR STREAM"
        case .ready:
            "STARTING…"
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: KTSpacing.xs) {
            HStack {
                Text("00:00:00")
                Spacer()
                Text("--:--:--")
            }
            .font(KTTypography.technicalMD().weight(.bold))
            .textCase(.uppercase)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HazardStripes()
                        .frame(width: geo.size.width * 0.75)
                    KTColor.tertiaryContainer
                        .frame(width: geo.size.width * 0.05)
                    Rectangle()
                        .fill(KTColor.primary)
                        .frame(width: 6, height: 40)
                        .offset(x: geo.size.width * 0.05 - 3, y: -4)
                        .overlay(Rectangle().strokeBorder(KTColor.onBackground, lineWidth: 2))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(KTColor.surfaceContainer)
                .thickBorder()
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
        return """
        FILE: \(path)
        SOURCE: LOCAL_HTTP_LOOPBACK
        PLAYBACK_URL: \(url)
        """
    }

    private func togglePlayPause() {
        #if os(macOS)
        guard let player else {
            isPlaying.toggle()
            return
        }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        #endif
        isPlaying.toggle()
    }

    #if os(macOS)
    private func rebuildPlayer(with url: URL?) {
        player?.pause()
        guard let url else {
            player = nil
            return
        }
        let next = AVPlayer(url: url)
        player = next
        next.play()
        isPlaying = true
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

#Preview {
    StreamingPlayerView()
        .environment(TorrentEngine())
}
