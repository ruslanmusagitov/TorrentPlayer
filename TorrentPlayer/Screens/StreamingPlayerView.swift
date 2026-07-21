//
//  StreamingPlayerView.swift
//  TorrentPlayer
//
//  Stub: design/streaming_player/
//

import SwiftUI

struct StreamingPlayerView: View {
    @State private var isPlaying = true
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
            ("DL_SPEED", "12.4 MB/s", KTColor.primary),
            ("PEERS_CONNECTED", "156 SEED / 42 LEECH", KTColor.secondary),
            ("ETA_REMAINING", "00:04:22", KTColor.onBackground),
            ("PROTOCOL", "UTP_V2_ENCRYPTED", KTColor.tertiary),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KTSpacing.md) {
                Text("S04E12_HIGH_VELOCITY_STREAM_X265.MKV")
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
    }

    private var playerCanvas: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0A1628), Color(hex: 0x1A0A14), KTColor.primary.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: KTSpacing.sm) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.85))
                Text("VIDEO STUB")
                    .font(KTTypography.technicalSM())
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(2)
            }

            VStack {
                HStack {
                    Text("● LIVE")
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
                        isPlaying.toggle()
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

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: KTSpacing.xs) {
            HStack {
                Text("00:42:15")
                Spacer()
                Text("01:58:30")
            }
            .font(KTTypography.technicalMD().weight(.bold))
            .textCase(.uppercase)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HazardStripes()
                        .frame(width: geo.size.width * 0.75)
                    KTColor.tertiaryContainer
                        .frame(width: geo.size.width * 0.35)
                    Rectangle()
                        .fill(KTColor.primary)
                        .frame(width: 6, height: 40)
                        .offset(x: geo.size.width * 0.35 - 3, y: -4)
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
            Text("""
            SOURCE: HD_BLURAY_REMUX
            CODEC: HEVC_MAIN_10@L5.1@HIGH
            AUDIO: DTS-HD_MASTER_7.1_48KHZ
            CONTAINER: MATROSKA_VERSION_4
            """)
            .font(KTTypography.technicalSM())
            .foregroundStyle(KTColor.onSurfaceVariant)
        }
        .padding(KTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KTColor.surface)
        .thickBorder()
        .hardShadow()
    }

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
}
