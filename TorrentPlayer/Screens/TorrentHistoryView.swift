//
//  TorrentHistoryView.swift
//  TorrentPlayer
//
//  Task #10: history list + reopen from design/torrent_history/
//

import SwiftData
import SwiftUI

struct TorrentHistoryView: View {
    @Environment(TorrentEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TorrentHistoryEntry.addedAt, order: .reverse)
    private var entries: [TorrentHistoryEntry]

    @State private var resumingInfoHash: String?
    @State private var resumeError: String?

    var onResume: (() -> Void)?

    private var isResuming: Bool {
        resumingInfoHash != nil || engine.isLoadingTorrent
    }

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

                if let resumeError {
                    Text(resumeError)
                        .font(KTTypography.technicalSM())
                        .foregroundStyle(KTColor.error)
                        .padding(KTSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(KTColor.errorContainer)
                        .thickBorder()
                }

                if entries.isEmpty {
                    Text("NO HISTORY ENTRIES YET")
                        .font(KTTypography.technicalMD())
                        .foregroundStyle(KTColor.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(entries) { entry in
                        historyCard(entry)
                    }
                }

                VStack(spacing: KTSpacing.sm) {
                    Text("END OF LOCAL HISTORY")
                        .font(KTTypography.labelCaps())
                        .tracking(1.1)
                    BrutalPrimaryButton(title: "Clear All History", systemImage: "trash") {
                        clearAll()
                    }
                    .disabled(entries.isEmpty || isResuming)
                    .opacity(entries.isEmpty || isResuming ? 0.45 : 1)
                }
                .padding(KTSpacing.lg)
                .frame(maxWidth: .infinity)
                .background(KTColor.surface)
                .overlay {
                    Rectangle()
                        .strokeBorder(
                            KTColor.onBackground,
                            style: StrokeStyle(lineWidth: KTSpacing.borderThick, dash: [8, 6])
                        )
                }
            }
            .padding(KTSpacing.md)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(KTColor.background)
    }

    private func historyCard(_ entry: TorrentHistoryEntry) -> some View {
        let available = !entry.magnetURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isThisResuming = resumingInfoHash == entry.infoHash

        return VStack(alignment: .leading, spacing: KTSpacing.sm) {
            HStack(spacing: KTSpacing.xs) {
                Text(entry.badgeLabel)
                    .font(KTTypography.labelCaps())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(entry.badgeColor)
                Text("ID: \(entry.shortID)")
                    .font(KTTypography.technicalSM())
                    .opacity(0.6)
            }

            Text(entry.displayName)
                .font(KTTypography.headlineLGMobile())
                .textCase(.uppercase)
                .lineLimit(1)

            Text(entry.magnetURI)
                .font(KTTypography.technicalSM().weight(.bold))
                .foregroundStyle(KTColor.primary)
                .lineLimit(1)
                .italic(!available)

            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                Text("ADDED: \(Self.addedFormatter.string(from: entry.addedAt))")
                    .font(KTTypography.technicalSM())
            }

            HStack(spacing: KTSpacing.sm) {
                if available {
                    BrutalSecondaryButton(
                        title: isThisResuming ? "Loading…" : "Resume",
                        systemImage: "play.fill",
                        foreground: KTColor.onTertiaryContainer,
                        background: KTColor.tertiaryContainer
                    ) {
                        Task { @MainActor in
                            await resume(entry)
                        }
                    }
                    .disabled(isResuming || !engine.isOperational)
                    .opacity(isResuming && !isThisResuming || !engine.isOperational ? 0.45 : 1)
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
                ) {
                    delete(entry)
                }
                .disabled(isResuming)
                .opacity(isResuming ? 0.45 : 1)
            }
        }
        .padding(KTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(available ? Color.white : KTColor.surfaceVariant.opacity(0.6))
        .thickBorder()
        .hardShadow(available ? KTSpacing.shadowOffset : 0)
        .opacity(available ? 1 : 0.85)
    }

    private func resume(_ entry: TorrentHistoryEntry) async {
        guard resumingInfoHash == nil else { return }
        resumeError = nil
        resumingInfoHash = entry.infoHash
        defer { resumingInfoHash = nil }

        do {
            try await engine.addMagnet(entry.magnetURI)
            onResume?()
        } catch {
            resumeError = error.localizedDescription
        }
    }

    private func delete(_ entry: TorrentHistoryEntry) {
        modelContext.delete(entry)
        do {
            try modelContext.save()
        } catch {
            TPLog.error("history delete failed: \(error.localizedDescription)")
        }
    }

    private func clearAll() {
        for entry in entries {
            modelContext.delete(entry)
        }
        do {
            try modelContext.save()
        } catch {
            TPLog.error("history clear failed: \(error.localizedDescription)")
        }
    }

    private static let addedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

extension TorrentHistoryEntry {
    var shortID: String {
        let compact = infoHash.replacingOccurrences(of: "-", with: "")
        guard compact.count >= 8 else { return compact.uppercased() }
        return String(compact.prefix(8)).uppercased()
    }

    var badgeLabel: String {
        let ext = (displayName as NSString).pathExtension.uppercased()
        if TorrentFileFormatting.isVideoExtension(ext) {
            return "VIDEO_\(ext)"
        }
        if !ext.isEmpty {
            return ext
        }
        return "TORRENT"
    }

    var badgeColor: Color {
        let ext = (displayName as NSString).pathExtension.lowercased()
        if TorrentFileFormatting.isVideoExtension(ext) {
            return KTColor.secondary
        }
        return KTColor.primary
    }
}

#Preview {
    TorrentHistoryView()
        .environment(TorrentEngine())
        .modelContainer(for: TorrentHistoryEntry.self, inMemory: true)
}
