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
    @State private var sortMode: FileSortMode = .name

    private var files: [TorrentFileItem] {
        let raw = engine.activeTorrent?.files ?? []
        switch sortMode {
        case .name:
            return raw.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .size:
            return raw.sorted { $0.size > $1.size }
        case .type:
            return raw.sorted {
                let l = ($0.name as NSString).pathExtension
                let r = ($1.name as NSString).pathExtension
                let ext = l.localizedCaseInsensitiveCompare(r)
                if ext != .orderedSame { return ext == .orderedAscending }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private var hasVideoSelection: Bool {
        engine.selectedFile != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: KTSpacing.lg) {
                    if let torrent = engine.activeTorrent {
                        activeTorrentHeader(torrent)
                    }

                    if engine.isLoadingTorrent {
                        loadingState
                    } else if engine.activeTorrent == nil {
                        emptyState
                    } else if files.isEmpty {
                        noFilesState
                    } else if engine.activeTorrent?.videoFiles.isEmpty == true {
                        noVideoState
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
            .disabled(!hasVideoSelection)
            .padding(KTSpacing.sm)
            .background(KTColor.surface)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(KTColor.onBackground)
                    .frame(height: KTSpacing.borderThin)
            }
        }
        .background(KTColor.background)
    }

    private var fileListSection: some View {
        Group {
            HStack {
                Text("File Contents (\(files.count))")
                    .font(KTTypography.labelCaps())
                    .textCase(.uppercase)
                    .tracking(1.1)
                Spacer()
                Button {
                    sortMode = sortMode.next
                } label: {
                    HStack(spacing: 4) {
                        Text("Sort by:")
                            .font(KTTypography.technicalSM())
                            .opacity(0.7)
                        Text(sortMode.label)
                            .font(KTTypography.technicalSM())
                            .underline()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sort by \(sortMode.label)")
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

    private var noFilesState: some View {
        VStack(spacing: KTSpacing.sm) {
            Image(systemName: "folder")
                .font(.system(size: 40))
            Text("NO FILES IN TORRENT")
                .font(KTTypography.labelCaps())
                .tracking(1.1)
            Text("This torrent loaded successfully but contains no files.")
                .font(KTTypography.bodyMD())
                .foregroundStyle(KTColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(KTSpacing.lg)
        .background(KTColor.surfaceContainerLowest)
        .thickBorder()
    }

    private var noVideoState: some View {
        VStack(spacing: KTSpacing.sm) {
            Image(systemName: "film.stack")
                .font(.system(size: 40))
            Text("NO VIDEO FILES")
                .font(KTTypography.labelCaps())
                .tracking(1.1)
            Text("This torrent has no playable video files (mkv, mp4, avi, mov, and similar).")
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
                let selected = engine.selectedFileID == file.id
                Button {
                    guard file.isVideo else { return }
                    engine.selectFile(id: file.id)
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

private enum FileSortMode: CaseIterable {
    case name
    case size
    case type

    var label: String {
        switch self {
        case .name: "Name"
        case .size: "Size"
        case .type: "Type"
        }
    }

    var next: FileSortMode {
        switch self {
        case .name: .size
        case .size: .type
        case .type: .name
        }
    }
}

#Preview {
    SelectFileView()
        .environment(TorrentEngine())
}
