//
//  LoadMagnetView.swift
//  TorrentPlayer
//
//  Stub: design/load_magnet/
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct LoadMagnetView: View {
    @Environment(TorrentEngine.self) private var engine
    @State private var magnetText = ""
    @State private var isLoading = false
    var onLoad: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KTSpacing.lg) {
                VStack(alignment: .leading, spacing: KTSpacing.sm) {
                    StatusChip(
                        text: engine.statusLabel,
                        background: statusChipColors.background,
                        foreground: statusChipColors.foreground
                    )
                    Text("INJECT\nMAGNET")
                        .font(KTTypography.display())
                        .foregroundStyle(KTColor.onBackground)
                        .textCase(.uppercase)
                        .lineSpacing(-4)
                    Text("Paste your peer-to-peer magnet link or hash below to initiate the streaming sequence.")
                        .font(KTTypography.bodyMD())
                        .foregroundStyle(KTColor.onSurfaceVariant)
                }

                VStack(alignment: .leading, spacing: KTSpacing.md) {
                    ZStack(alignment: .topTrailing) {
                        MagnetURIEditor(text: $magnetText)
                            .frame(minHeight: 160)
                            .background(KTColor.surfaceContainerLowest)
                            .thickBorder()
                            .hardShadow()

                        HStack(spacing: KTSpacing.xs) {
                            miniAction("PASTE") {
                                #if os(macOS)
                                if let pasted = NSPasteboard.general.string(forType: .string) {
                                    magnetText = pasted
                                }
                                #else
                                if let pasted = UIPasteboard.general.string {
                                    magnetText = pasted
                                }
                                #endif
                            }
                            miniAction("CLEAR") { magnetText = "" }
                        }
                        .padding(KTSpacing.xs)
                    }

                    BrutalPrimaryButton(
                        title: isLoading ? "Loading…" : "Load Magnet",
                        systemImage: "bolt.fill",
                        largeShadow: true
                    ) {
                        Task { await loadMagnet() }
                    }
                    .disabled(isLoading || !engine.isOperational)
                    .opacity(isLoading || !engine.isOperational ? 0.45 : 1)
                }

                awaitingStreamCard

                HStack(spacing: KTSpacing.md) {
                    statCard(label: "Network Load", value: "88.2", unit: "MB/S")
                    statCard(label: "Connected", value: "412", unit: "PEERS", valueColor: KTColor.tertiary)
                }
            }
            .padding(KTSpacing.md)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(KTColor.background)
    }

    private var statusChipColors: (background: Color, foreground: Color) {
        switch engine.phase {
        case .error:
            (KTColor.errorContainer, KTColor.error)
        case .unsupportedPlatform:
            (KTColor.secondaryFixed, KTColor.secondary)
        case .ready, .loaded:
            (KTColor.tertiaryContainer, KTColor.onTertiaryContainer)
        case .fetchingMetadata, .adding:
            (KTColor.primaryContainer, KTColor.onPrimary)
        default:
            (KTColor.surfaceContainer, KTColor.onSurfaceVariant)
        }
    }

    private var awaitingStreamCard: some View {
        ZStack {
            KTColor.secondary
            VStack(spacing: KTSpacing.xs) {
                Image(systemName: "sensor.tag.radiowaves.forward")
                    .font(.system(size: 48, weight: .regular))
                switch engine.phase {
                case .fetchingMetadata, .adding:
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                    Text("Fetching Metadata…")
                        .font(KTTypography.technicalSM())
                        .textCase(.uppercase)
                        .tracking(2)
                    Text("Contacting trackers / DHT for file list")
                        .font(KTTypography.technicalSM())
                        .opacity(0.8)
                        .multilineTextAlignment(.center)
                case let .loaded(torrent):
                    Text(torrent.displayName.uppercased())
                        .font(KTTypography.technicalSM())
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                    Text("\(torrent.files.count) files • \(torrent.formattedTotalSize.uppercased())")
                        .font(KTTypography.technicalSM())
                        .opacity(0.8)
                    Text(torrent.infoHash)
                        .font(KTTypography.technicalSM())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .opacity(0.8)
                case let .error(message):
                    Text("LOAD FAILED")
                        .font(KTTypography.technicalSM())
                        .textCase(.uppercase)
                        .tracking(2)
                    Text(message)
                        .font(KTTypography.technicalSM())
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .opacity(0.9)
                default:
                    Text("Awaiting Active Stream")
                        .font(KTTypography.technicalSM())
                        .textCase(.uppercase)
                        .tracking(2)
                    Text("Paste a magnet, then tap Load Magnet")
                        .font(KTTypography.technicalSM())
                        .opacity(0.8)
                }
            }
            .foregroundStyle(.white)
            .padding(KTSpacing.lg)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .thickBorder()
        .hardShadow()
    }

    private func statCard(label: String, value: String, unit: String, valueColor: Color = KTColor.onBackground) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(KTTypography.labelCaps())
                .foregroundStyle(KTColor.outline)
                .tracking(1.1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(KTTypography.headlineLGMobile())
                    .foregroundStyle(valueColor)
                Text(unit)
                    .font(KTTypography.technicalSM())
                    .foregroundStyle(valueColor)
            }
        }
        .padding(KTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KTColor.surface)
        .thickBorder()
        .hardShadow()
    }

    private func miniAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(KTTypography.technicalSM())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(KTColor.surface)
                .overlay(Rectangle().strokeBorder(KTColor.onBackground, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func loadMagnet() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await engine.addMagnet(magnetText)
            onLoad?()
        } catch {
            // Engine already set .error / restored previous torrent for UI feedback.
        }
    }
}

#Preview {
    LoadMagnetView()
        .environment(TorrentEngine())
}
