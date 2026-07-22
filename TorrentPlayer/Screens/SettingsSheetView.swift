//
//  SettingsSheetView.swift
//  TorrentPlayer
//
//  Storage paths, disk usage, Clear Downloads / Clear Resume.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SettingsSheetView: View {
    @Environment(TorrentEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var diskUsageBytes: Int64 = 0
    @State private var statusMessage: String?
    @State private var isClearing = false
    @State private var confirmClearDownloads = false
    @State private var confirmClearResume = false

    private var downloadsPath: String {
        (try? TorrentEngine.downloadsDirectory().path) ?? "—"
    }

    private var logsPath: String {
        TPLog.logFileURL?.path
            ?? ((try? TorrentEngine.logsDirectory().appendingPathComponent("debug.log").path) ?? "—")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(KTTypography.headlineLGMobile())
                    .textCase(.uppercase)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(KTColor.onBackground)
                        .frame(width: 40, height: 40)
                        .background(KTColor.surface)
                        .thickBorder()
                }
                .buttonStyle(.plain)
            }
            .padding(KTSpacing.md)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(KTColor.onBackground)
                    .frame(height: KTSpacing.borderThick)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: KTSpacing.lg) {
                    if let statusMessage {
                        Text(statusMessage)
                            .font(KTTypography.technicalSM())
                            .foregroundStyle(KTColor.onTertiaryContainer)
                            .padding(KTSpacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(KTColor.tertiaryContainer)
                            .thickBorder()
                    }

                    pathCard(
                        title: "Downloads",
                        path: downloadsPath,
                        detail: "ON DISK: \(TorrentFileFormatting.formatSize(diskUsageBytes).uppercased())"
                    ) {
                        revealOrCopy(url: try? TorrentEngine.downloadsDirectory())
                    }

                    pathCard(
                        title: "Logs",
                        path: logsPath,
                        detail: nil
                    ) {
                        if let url = TPLog.logFileURL {
                            revealOrCopy(url: url.deletingLastPathComponent())
                        } else {
                            revealOrCopy(url: try? TorrentEngine.logsDirectory())
                        }
                    }

                    VStack(spacing: KTSpacing.sm) {
                        BrutalSecondaryButton(
                            title: isClearing ? "Working…" : "Clear Downloads",
                            systemImage: "trash",
                            foreground: KTColor.error,
                            background: .white
                        ) {
                            confirmClearDownloads = true
                        }
                        .disabled(isClearing)
                        .opacity(isClearing ? 0.45 : 1)

                        BrutalSecondaryButton(
                            title: "Clear Resume Data",
                            systemImage: "arrow.counterclockwise",
                            foreground: KTColor.onBackground,
                            background: .white
                        ) {
                            confirmClearResume = true
                        }
                        .disabled(isClearing)
                        .opacity(isClearing ? 0.45 : 1)
                    }
                }
                .padding(KTSpacing.md)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(KTColor.background)
        .onAppear { refreshUsage() }
        .confirmationDialog(
            "Delete all downloaded torrent files from disk?",
            isPresented: $confirmClearDownloads,
            titleVisibility: .visible
        ) {
            Button("Clear Downloads", role: .destructive) {
                Task { await clearDownloads() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete resume piece data? Active downloads will restart from scratch next time.",
            isPresented: $confirmClearResume,
            titleVisibility: .visible
        ) {
            Button("Clear Resume Data", role: .destructive) {
                clearResume()
            }
            Button("Cancel", role: .cancel) {}
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }

    private func pathCard(
        title: String,
        path: String,
        detail: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: KTSpacing.sm) {
            Text(title.uppercased())
                .font(KTTypography.labelCaps())
                .tracking(1.1)
                .foregroundStyle(KTColor.outline)

            Text(path)
                .font(KTTypography.technicalSM().weight(.bold))
                .foregroundStyle(KTColor.primary)
                .textSelection(.enabled)
                .lineLimit(3)

            if let detail {
                Text(detail)
                    .font(KTTypography.technicalSM())
                    .foregroundStyle(KTColor.onSurfaceVariant)
            }

            BrutalSecondaryButton(
                title: revealButtonTitle,
                systemImage: revealButtonImage,
                foreground: KTColor.onBackground,
                background: KTColor.surface
            ) {
                action()
            }
        }
        .padding(KTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KTColor.surface)
        .thickBorder()
        .hardShadow()
    }

    private var revealButtonTitle: String {
        #if os(macOS)
        "Reveal in Finder"
        #else
        "Copy Path"
        #endif
    }

    private var revealButtonImage: String {
        #if os(macOS)
        "folder"
        #else
        "doc.on.doc"
        #endif
    }

    private func revealOrCopy(url: URL?) {
        guard let url else {
            statusMessage = "Path unavailable"
            return
        }
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        statusMessage = "Revealed in Finder"
        #else
        UIPasteboard.general.string = url.path
        statusMessage = "Path copied"
        #endif
    }

    private func refreshUsage() {
        diskUsageBytes = TorrentEngine.downloadsDiskUsageBytes()
    }

    private func clearDownloads() async {
        guard !isClearing else { return }
        isClearing = true
        defer { isClearing = false }
        do {
            try await engine.clearDownloads()
            refreshUsage()
            statusMessage = "Downloads cleared"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func clearResume() {
        guard !isClearing else { return }
        isClearing = true
        defer { isClearing = false }
        do {
            try engine.clearResumeData()
            statusMessage = "Resume data cleared"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

#Preview {
    SettingsSheetView()
        .environment(TorrentEngine())
}
