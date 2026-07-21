//
//  SelectFileView.swift
//  TorrentPlayer
//
//  design/select_file/
//

import SwiftUI

struct SelectFileView: View {
    @Environment(TorrentEngine.self) private var engine
    var onStream: (() -> Void)?

    @State private var selectedID: Int?

    private var files: [TorrentFileItem] {
        engine.activeTorrent?.files ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: KTSpacing.lg) {
                    if let torrent = engine.activeTorrent {
                        activeTorrentHeader(torrent)
                    }

                    if case .fetchingMetadata = engine.phase {
                        loadingState
                    } else if engine.activeTorrent == nil {
                        emptyState
                    } else {
                        fileListSection
                    }
                }
                .padding(KTSpacing.md)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            BrutalPrimaryButton(title: "Stream Now", systemImage: "play.fill") {
                onStream?()
            }
            .disabled(engine.activeTorrent == nil)
            .padding(KTSpacing.sm)
            .background(KTColor.surface)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(KTColor.onBackground)
                    .frame(height: KTSpacing.borderThin)
            }
        }
        .background(KTColor.background)
        .onChange(of: engine.activeTorrent?.files.count) { _, _ in
            selectedID = engine.activeTorrent?.files.first?.id
        }
        .onAppear {
            if selectedID == nil {
                selectedID = engine.activeTorrent?.files.first?.id
            }
        }
    }

    private var fileListSection: some View {
        Group {
            HStack {
                Text("File Contents (\(files.count))")
                    .font(KTTypography.labelCaps())
                    .textCase(.uppercase)
                    .tracking(1.1)
                Spacer()
                HStack(spacing: 4) {
                    Text("Sort by:")
                        .font(KTTypography.technicalSM())
                        .opacity(0.7)
                    Text("Name")
                        .font(KTTypography.technicalSM())
                        .underline()
                }
            }

            fileList
        }
    }

    private var loadingState: some View {
        VStack(spacing: KTSpacing.sm) {
            ProgressView()
                .controlSize(.large)
            Text("FETCHING METADATA…")
                .font(KTTypography.labelCaps())
                .tracking(1.1)
        }
        .frame(maxWidth: .infinity)
        .padding(KTSpacing.lg)
        .background(KTColor.surfaceContainerLowest)
        .thickBorder()
    }

    private var emptyState: some View {
        VStack(spacing: KTSpacing.sm) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40))
            Text("LOAD A MAGNET FIRST")
                .font(KTTypography.labelCaps())
                .tracking(1.1)
            Text("Paste a magnet link on the Load screen to see file contents here.")
                .font(KTTypography.bodyMD())
                .foregroundStyle(KTColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(KTSpacing.lg)
        .background(KTColor.surfaceContainerLowest)
        .thickBorder()
    }

    private func activeTorrentHeader(_ torrent: ActiveTorrent) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: KTSpacing.xs) {
                Text("ACTIVE_TORRENT")
                    .font(KTTypography.labelCaps())
                    .foregroundStyle(KTColor.secondaryFixed)
                    .tracking(1.1)
                Text(torrent.displayName)
                    .font(KTTypography.headlineLGMobile())
                    .foregroundStyle(KTColor.onSecondary)
                    .textCase(.uppercase)
            }
            Spacer(minLength: KTSpacing.sm)
            Text("SIZE: \(torrent.formattedTotalSize.uppercased())")
                .font(KTTypography.technicalMD())
                .foregroundStyle(KTColor.secondary)
                .padding(KTSpacing.xs)
                .background(KTColor.onSecondary)
                .thickBorder()
        }
        .padding(KTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KTColor.secondary)
        .thickBorder()
        .hardShadow()
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            ForEach(files) { file in
                let selected = selectedID == file.id
                Button {
                    selectedID = file.id
                } label: {
                    HStack(spacing: KTSpacing.md) {
                        Image(systemName: iconName(for: file))
                            .font(.system(size: 22, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(selected ? KTTypography.headlineLGMobile() : KTTypography.bodyMD().weight(.bold))
                                .textCase(.uppercase)
                                .lineLimit(1)
                            Text(file.detail)
                                .font(KTTypography.technicalSM())
                                .opacity(selected ? 0.8 : 0.6)
                        }
                        Spacer()
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 22))
                    }
                    .foregroundStyle(selected ? KTColor.onTertiaryContainer : KTColor.onBackground)
                    .padding(KTSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selected ? KTColor.tertiaryContainer : KTColor.surfaceContainerLowest)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(KTColor.onBackground)
                    .frame(height: (selected || file.isVideo) ? KTSpacing.borderThick : KTSpacing.borderThin)
            }
        }
        .thickBorder()
    }

    private func iconName(for file: TorrentFileItem) -> String {
        if file.isVideo {
            return "film"
        }
        let ext = (file.name as NSString).pathExtension.lowercased()
        switch ext {
        case "srt", "vtt", "ass":
            return "captions.bubble"
        case "jpg", "jpeg", "png", "gif", "webp":
            return "photo"
        default:
            return "doc.text"
        }
    }
}

#Preview {
    SelectFileView()
        .environment(TorrentEngine())
}
