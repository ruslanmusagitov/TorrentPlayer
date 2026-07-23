//
//  SplashScreenView.swift
//  TorrentPlayer
//
//  design/splash_screen/
//

import SwiftUI

struct SplashScreenView: View {
    var bootStep: TorrentEngine.BootStep
    var bootProgress: Double
    var onFinished: () -> Void

    @State private var didFinish = false

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v.\(version)_STABLE"
    }

    private var isTerminal: Bool {
        bootStep.isTerminal
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
        .task(id: isTerminal) {
            await finishIfPossible()
        }
        .onChange(of: bootStep) { _, _ in
            Task { await finishIfPossible() }
        }
        .onChange(of: bootProgress) { _, _ in
            Task { await finishIfPossible() }
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
                        .frame(width: max(0, geo.size.width * bootProgress))
                }

                HazardStripes()
                    .opacity(0.12)
            }
            .frame(height: 32)
            .thickBorder()
            .animation(.easeOut(duration: 0.2), value: bootProgress)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bootStep.statusLine)
                        .font(KTTypography.technicalMD())
                        .foregroundStyle(isTerminal && bootStep == .ready ? KTColor.tertiary : KTColor.onBackground)
                        .textCase(.uppercase)
                    Text(bootStep.secondaryLine)
                        .font(KTTypography.technicalSM())
                        .foregroundStyle(KTColor.onBackground.opacity(0.6))
                        .lineLimit(2)
                }
                Spacer()
                Text("\(Int(bootProgress * 100))%")
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
    private func finishIfPossible() async {
        guard !didFinish else { return }
        guard bootStep.isTerminal, bootProgress >= 1 else { return }
        didFinish = true
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
    SplashScreenView(bootStep: .bootstrappingDHT, bootProgress: 0.85, onFinished: {})
}
