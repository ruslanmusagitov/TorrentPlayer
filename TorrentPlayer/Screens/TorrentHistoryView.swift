//
//  TorrentHistoryView.swift
//  TorrentPlayer
//
//  Stub: design/torrent_history/
//

import SwiftUI

private struct StubHistoryEntry: Identifiable {
    let id: String
    let badge: String
    let badgeColor: Color
    let title: String
    let magnet: String
    let added: String
    let available: Bool
}

struct TorrentHistoryView: View {
    var onResume: (() -> Void)?

    private let entries: [StubHistoryEntry] = [
        .init(
            id: "TRN_9921_X",
            badge: "VIDEO_MKV",
            badgeColor: KTColor.secondary,
            title: "Interstellar.2014.REMASTERED.2160p.10bit.HDR",
            magnet: "magnet:?xt=urn:btih:8f3c7...9e2a1b5c&dn=Interstellar",
            added: "2023-10-24 14:32:01",
            available: true
        ),
        .init(
            id: "TRN_1120_B",
            badge: "ISO_IMAGE",
            badgeColor: KTColor.primary,
            title: "Ubuntu-22.04.3-Desktop-AMD64.iso",
            magnet: "magnet:?xt=urn:btih:3f2a1...4e8b9c0d&dn=Ubuntu",
            added: "2023-10-22 09:15:44",
            available: true
        ),
        .init(
            id: "TRN_4456_F",
            badge: "AUDIO_PACK",
            badgeColor: KTColor.secondary,
            title: "FLAC_Archive_2023_HighRes_Lossless",
            magnet: "magnet:?xt=urn:btih:1a2b3...c4d5e6f7&dn=Audio",
            added: "2023-10-18 22:59:10",
            available: true
        ),
        .init(
            id: "TRN_0000_E",
            badge: "FILE_UNKNOWN",
            badgeColor: KTColor.onBackground,
            title: "Corrupted_Metadata_Stream_V3",
            magnet: "Source unavailable / Magnet link expired",
            added: "2023-09-30 11:11:11",
            available: false
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KTSpacing.lg) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("History")
                        .font(KTTypography.display())
                        .textCase(.uppercase)
                    Text("ARCHIVE OF LOADED PEER-TO-PEER STREAMS. DATA RETENTION IS LOCAL AND PERSISTENT UNTIL MANUAL CLEARANCE.")
                        .font(KTTypography.technicalMD())
                        .padding(.leading, KTSpacing.sm)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(KTColor.primary)
                                .frame(width: KTSpacing.borderThick)
                        }
                }

                ForEach(entries) { entry in
                    historyCard(entry)
                }

                VStack(spacing: KTSpacing.sm) {
                    Text("END OF LOCAL HISTORY")
                        .font(KTTypography.labelCaps())
                        .tracking(1.1)
                    BrutalPrimaryButton(title: "Clear All History", systemImage: "trash") {}
                }
                .padding(KTSpacing.lg)
                .frame(maxWidth: .infinity)
                .background(KTColor.surface)
                .overlay {
                    Rectangle()
                        .strokeBorder(KTColor.onBackground, style: StrokeStyle(lineWidth: KTSpacing.borderThick, dash: [8, 6]))
                }
            }
            .padding(KTSpacing.md)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(KTColor.background)
    }

    private func historyCard(_ entry: StubHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: KTSpacing.sm) {
            HStack(spacing: KTSpacing.xs) {
                Text(entry.badge)
                    .font(KTTypography.labelCaps())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(entry.badgeColor)
                Text("ID: \(entry.id)")
                    .font(KTTypography.technicalSM())
                    .opacity(0.6)
            }

            Text(entry.title)
                .font(KTTypography.headlineLGMobile())
                .textCase(.uppercase)
                .lineLimit(1)

            Text(entry.magnet)
                .font(KTTypography.technicalSM().weight(.bold))
                .foregroundStyle(KTColor.primary)
                .lineLimit(1)
                .italic(!entry.available)

            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                Text("ADDED: \(entry.added)")
                    .font(KTTypography.technicalSM())
            }

            HStack(spacing: KTSpacing.sm) {
                if entry.available {
                    BrutalSecondaryButton(
                        title: "Resume",
                        systemImage: "play.fill",
                        foreground: KTColor.onTertiaryContainer,
                        background: KTColor.tertiaryContainer
                    ) {
                        onResume?()
                    }
                } else {
                    Text("UNAVAILABLE")
                        .font(KTTypography.labelCaps())
                        .tracking(1.1)
                        .foregroundStyle(KTColor.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, KTSpacing.sm)
                        .background(KTColor.surfaceDim)
                        .thickBorder()
                }

                BrutalSecondaryButton(
                    title: "Delete",
                    systemImage: "trash",
                    foreground: KTColor.error,
                    background: .white
                ) {}
            }
        }
        .padding(KTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(entry.available ? Color.white : KTColor.surfaceVariant.opacity(0.6))
        .thickBorder()
        .hardShadow(entry.available ? KTSpacing.shadowOffset : 0)
        .opacity(entry.available ? 1 : 0.85)
    }
}

#Preview {
    TorrentHistoryView()
}
