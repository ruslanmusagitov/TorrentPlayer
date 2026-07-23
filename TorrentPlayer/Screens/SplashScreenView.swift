//
//  SplashScreenView.swift
//  TorrentPlayer
//
//  design/splash_screen/
//

import SwiftUI

struct SplashScreenView: View {
    var isReady: Bool
    var onFinished: () -> Void

    @State private var progress: Double = 0.12
    @State private var statusIndex = 0
    @State private var statusPulse = true
    @State private var didFinish = false

    private let statuses = [
        "> INITIALIZING_CORE_ENGINE...",
        "> SYNCING_DHT_PROTOCOLS...",
        "> VERIFYING_BLOCK_INTEGRITY...",
        "> ALLOCATING_BUFFER_SPACE...",
        "> HANDSHAKING_PEER_NODES...",
    ]

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v.\(version)_STABLE"
    }

    var body: some View {
        ZStack {
            KTColor.background.ignoresSafeArea()
            DotGridOverlay()
                .opacity(0.03)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                Spacer(minLength: KTSpacing.md)
                brandBlock
                Spacer(minLength: KTSpacing.md)
                statusSection
            }
            .padding(KTSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KTColor.background)
            .thickBorder()
            .hardShadow(KTSpacing.shadowOffsetLarge)
            .padding(KTSpacing.md)

            cornerAccents
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Torrent Player launching")
        .task { await runBootSequence() }
        .onChange(of: isReady) { _, ready in
            if ready { Task { await finishIfPossible(forceComplete: true) } }
        }
    }

    private var headerBar: some View {
        HStack(alignment: .top) {
            HStack(spacing: KTSpacing.xs) {
                ColorSwatch(KTColor.primary)
                ColorSwatch(KTColor.tertiary)
                ColorSwatch(KTColor.secondary)
            }
            Spacer()
            Text(versionLabel)
                .font(KTTypography.technicalSM())
                .foregroundStyle(KTColor.onBackground)
                .padding(.horizontal, KTSpacing.xs)
                .padding(.vertical, 4)
                .background(KTColor.surfaceContainerHighest)
                .overlay(Rectangle().strokeBorder(KTColor.onBackground, lineWidth: 2))
        }
    }

    private var brandBlock: some View {
        VStack(spacing: KTSpacing.md) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 64, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(KTColor.onTertiaryContainer)
                .padding(KTSpacing.sm)
                .background(KTColor.tertiaryContainer)
                .thickBorder()
                .hardShadow()
                .rotationEffect(.degrees(-3))

            Text("TORRENT\nPLAYER")
                .font(KTTypography.display())
                .foregroundStyle(KTColor.primary)
                .italic()
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
                .tracking(-1)
                .lineSpacing(-6)

            Text("High Speed P2P Streaming Engine")
                .font(KTTypography.labelCaps())
                .foregroundStyle(KTColor.background)
                .textCase(.uppercase)
                .tracking(1.1)
                .padding(.horizontal, KTSpacing.md)
                .padding(.vertical, KTSpacing.base)
                .background(KTColor.onBackground)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: KTSpacing.sm) {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(KTColor.surfaceContainerHighest)

                GeometryReader { geo in
                    Rectangle()
                        .fill(KTColor.tertiary)
                        .frame(width: max(0, geo.size.width * progress))
                }

                HazardStripes()
                    .opacity(0.12)
            }
            .frame(height: 32)
            .thickBorder()

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(didFinish ? "> ENGINE_READY_STABLE" : statuses[statusIndex])
                        .font(KTTypography.technicalMD())
                        .foregroundStyle(didFinish ? KTColor.tertiary : KTColor.onBackground)
                        .textCase(.uppercase)
                        .opacity(statusPulse || didFinish ? 1 : 0.75)
                    Text("ESTABLISHING_DHT_NODE_NETWORK")
                        .font(KTTypography.technicalSM())
                        .foregroundStyle(KTColor.onBackground.opacity(0.6))
                }
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(KTTypography.technicalMD())
                    .fontWeight(.bold)
                    .foregroundStyle(KTColor.onBackground)
            }
        }
    }

    private var cornerAccents: some View {
        ZStack {
            Text("01010101\n10101010\n01010101")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(KTColor.onBackground.opacity(0.2))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(KTSpacing.sm + KTSpacing.md)

            Text("SEED: 242\nPEER: 1.2k")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(KTColor.onBackground.opacity(0.2))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(KTSpacing.sm + KTSpacing.md)
        }
        .allowsHitTesting(false)
    }

    @MainActor
    private func runBootSequence() async {
        while !didFinish {
            try? await Task.sleep(for: .milliseconds(200))
            let step = isReady ? Double.random(in: 0.04...0.08) : Double.random(in: 0.008...0.025)
            progress = min(isReady ? 1 : 0.92, progress + step)
            if Double.random(in: 0...1) > 0.8 {
                statusIndex = (statusIndex + 1) % statuses.count
            }
            statusPulse.toggle()
            await finishIfPossible(forceComplete: false)
        }
    }

    @MainActor
    private func finishIfPossible(forceComplete: Bool) async {
        guard !didFinish else { return }
        guard isReady else { return }
        if forceComplete {
            progress = 1
        }
        guard progress >= 1 else { return }
        didFinish = true
        statusPulse = true
        try? await Task.sleep(for: .milliseconds(350))
        onFinished()
    }
}

private struct ColorSwatch: View {
    let color: Color

    init(_ color: Color) {
        self.color = color
    }

    var body: some View {
        color
            .frame(width: 16, height: 16)
            .overlay(Rectangle().strokeBorder(KTColor.onBackground, lineWidth: 2))
    }
}

private struct DotGridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 20
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let rect = CGRect(x: x, y: y, width: 1, height: 1)
                    context.fill(Path(ellipseIn: rect), with: .color(KTColor.onBackground))
                    x += step
                }
                y += step
            }
        }
    }
}

#Preview {
    SplashScreenView(isReady: false, onFinished: {})
}
