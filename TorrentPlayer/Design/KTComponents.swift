//
//  KTComponents.swift
//  TorrentPlayer
//
//  Shared neo-brutalist UI primitives for Kinetic Torrent stubs.
//

import SwiftUI

struct HardShadow: ViewModifier {
    var offset: CGFloat = KTSpacing.shadowOffset
    var color: Color = KTColor.onBackground

    func body(content: Content) -> some View {
        content.shadow(color: color, radius: 0, x: offset, y: offset)
    }
}

extension View {
    func hardShadow(_ offset: CGFloat = KTSpacing.shadowOffset) -> some View {
        modifier(HardShadow(offset: offset))
    }

    func thickBorder(_ color: Color = KTColor.onBackground) -> some View {
        overlay(Rectangle().strokeBorder(color, lineWidth: KTSpacing.borderThick))
    }
}

struct BrutalPressStyle: ButtonStyle {
    var largeShadow: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .hardShadow(
                configuration.isPressed
                    ? 0
                    : (largeShadow ? KTSpacing.shadowOffsetLarge : KTSpacing.shadowOffset)
            )
            .offset(
                x: configuration.isPressed ? KTSpacing.shadowOffset : 0,
                y: configuration.isPressed ? KTSpacing.shadowOffset : 0
            )
    }
}

struct BrutalPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var largeShadow: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: KTSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .bold))
                }
                Text(title)
                    .font(KTTypography.headlineLGMobile())
                    .textCase(.uppercase)
            }
            .foregroundStyle(KTColor.onPrimaryContainer)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(KTColor.primaryContainer)
            .thickBorder()
        }
        .buttonStyle(BrutalPressStyle(largeShadow: largeShadow))
    }
}

struct BrutalSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var foreground: Color = KTColor.onBackground
    var background: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: KTSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(KTTypography.labelCaps())
                    .textCase(.uppercase)
                    .tracking(1.1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, KTSpacing.md)
            .padding(.vertical, KTSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(background)
            .thickBorder()
        }
        .buttonStyle(BrutalPressStyle())
    }
}

struct StatusChip: View {
    let text: String
    var background: Color = KTColor.tertiaryContainer
    var foreground: Color = KTColor.onTertiaryContainer

    var body: some View {
        Text(text.uppercased())
            .font(KTTypography.technicalSM())
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .overlay(Rectangle().strokeBorder(KTColor.onBackground, lineWidth: 1))
    }
}

struct AppHeaderBar: View {
    var body: some View {
        HStack {
            HStack(spacing: KTSpacing.xs) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(KTColor.primary)
                Text("TORRENT_PLAYER")
                    .font(KTTypography.headlineLGMobile())
                    .foregroundStyle(KTColor.primary)
                    .italic()
                    .textCase(.uppercase)
                    .tracking(-0.5)
            }
            Spacer()
            Button {
                // Settings stub
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(KTColor.onBackground)
                    .frame(width: 48, height: 48)
                    .background(KTColor.surface)
                    .thickBorder()
                    .hardShadow()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KTSpacing.md)
        .frame(height: KTSpacing.headerHeight)
        .background(KTColor.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(KTColor.onBackground)
                .frame(height: KTSpacing.borderThick)
        }
        .hardShadow()
        .zIndex(10)
    }
}

enum AppDestination: String, CaseIterable, Identifiable, Hashable {
    case load
    case files
    case player
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .load: "LOAD"
        case .files: "FILES"
        case .player: "PLAYER"
        case .history: "HISTORY"
        }
    }

    var systemImage: String {
        switch self {
        case .load: "plus.rectangle"
        case .files: "folder"
        case .player: "play.circle"
        case .history: "clock.arrow.circlepath"
        }
    }
}

struct SideNavBar: View {
    @Binding var selection: AppDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NAVIGATION")
                .font(KTTypography.labelCaps())
                .foregroundStyle(KTColor.outline)
                .tracking(1.1)
                .padding(.horizontal, KTSpacing.md)
                .padding(.bottom, KTSpacing.lg)

            ForEach(AppDestination.allCases) { destination in
                Button {
                    selection = destination
                } label: {
                    HStack(spacing: KTSpacing.sm) {
                        Image(systemName: destination.systemImage)
                        Text(destination.title)
                            .font(KTTypography.labelCaps())
                            .tracking(1.1)
                    }
                    .foregroundStyle(selection == destination ? KTColor.onPrimary : KTColor.onBackground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, KTSpacing.md)
                    .padding(.vertical, KTSpacing.sm)
                    .background(selection == destination ? KTColor.primary : Color.clear)
                    .overlay(alignment: .bottom) {
                        if selection != destination {
                            Rectangle()
                                .fill(KTColor.onBackground)
                                .frame(height: KTSpacing.borderThin)
                        }
                    }
                    .thickBorder(selection == destination ? KTColor.onBackground : .clear)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.top, KTSpacing.md)
        .frame(width: KTSpacing.sideNavWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(KTColor.surface)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(KTColor.onBackground)
                .frame(width: KTSpacing.borderThick)
        }
    }
}

struct BottomNavBar: View {
    @Binding var selection: AppDestination

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppDestination.allCases) { destination in
                Button {
                    selection = destination
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: destination.systemImage)
                            .font(.system(size: 20, weight: .medium))
                        Text(destination.title)
                            .font(KTTypography.labelCaps())
                            .tracking(0.8)
                    }
                    .foregroundStyle(
                        selection == destination
                            ? KTColor.onTertiaryContainer
                            : KTColor.onBackground
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        selection == destination
                            ? KTColor.tertiaryContainer
                            : KTColor.background
                    )
                    .overlay(alignment: .trailing) {
                        if destination != .history {
                            Rectangle()
                                .fill(KTColor.onBackground)
                                .frame(width: KTSpacing.borderThick)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: KTSpacing.bottomNavHeight)
        .background {
            KTColor.background.ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(KTColor.onBackground)
                .frame(height: KTSpacing.borderThick)
        }
    }
}

struct HazardStripes: View {
    var body: some View {
        Canvas { context, size in
            let stripeWidth: CGFloat = 10
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + stripeWidth, y: 0))
                path.addLine(to: CGPoint(x: x + stripeWidth + size.height, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(KTColor.onBackground))
                x += stripeWidth * 2
            }
        }
        .background(KTColor.surfaceVariant)
    }
}
