//
//  SelectFileView.swift
//  TorrentPlayer
//
//  Stub: design/select_file/
//

import SwiftUI

private struct StubTorrentFile: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let isVideo: Bool
}

struct SelectFileView: View {
    var onStream: (() -> Void)?

    @State private var selectedID = "1"

    private let files: [StubTorrentFile] = [
        .init(id: "1", name: "Interstellar.2014.Main.mkv", detail: "46.5 GB • Video/MKV", isVideo: true),
        .init(id: "2", name: "English_Subs.srt", detail: "156 KB • Text/SRT", isVideo: false),
        .init(id: "3", name: "Torrent_Info.txt", detail: "2 KB • Text/Plain", isVideo: false),
        .init(id: "4", name: "Interstellar.Behind.The.Scenes.mp4", detail: "1.2 GB • Video/MP4", isVideo: true),
        .init(id: "5", name: "Poster_HighRes.jpg", detail: "8.4 MB • Image/JPG", isVideo: false),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: KTSpacing.lg) {
                    activeTorrentHeader

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
                .padding(KTSpacing.md)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            BrutalPrimaryButton(title: "Stream Now", systemImage: "play.fill") {
                onStream?()
            }
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

    private var activeTorrentHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: KTSpacing.xs) {
                Text("ACTIVE_TORRENT")
                    .font(KTTypography.labelCaps())
                    .foregroundStyle(KTColor.secondaryFixed)
                    .tracking(1.1)
                Text("Interstellar.2014.2160p.HDR.x265.torrent")
                    .font(KTTypography.headlineLGMobile())
                    .foregroundStyle(KTColor.onSecondary)
                    .textCase(.uppercase)
            }
            Spacer(minLength: KTSpacing.sm)
            Text("SIZE: 48.2 GB")
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
                        Image(systemName: file.isVideo ? "film" : (file.name.hasSuffix(".srt") ? "captions.bubble" : "doc.text"))
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
}

#Preview {
    SelectFileView()
}
