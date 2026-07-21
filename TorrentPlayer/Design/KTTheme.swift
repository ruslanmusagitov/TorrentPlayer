//
//  KTTheme.swift
//  TorrentPlayer
//
//  Kinetic Torrent design tokens from design/kinetic_torrent/DESIGN.md
//

import SwiftUI

enum KTColor {
    static let background = Color(hex: 0xF9F9F9)
    static let onBackground = Color(hex: 0x1B1B1B)
    static let surface = Color(hex: 0xF9F9F9)
    static let surfaceContainer = Color(hex: 0xEEEEEE)
    static let surfaceContainerLowest = Color(hex: 0xFFFFFF)
    static let surfaceContainerHighest = Color(hex: 0xE2E2E2)
    static let surfaceVariant = Color(hex: 0xE2E2E2)
    static let surfaceDim = Color(hex: 0xDADADA)

    static let onSurface = Color(hex: 0x1B1B1B)
    static let onSurfaceVariant = Color(hex: 0x5A4136)
    static let outline = Color(hex: 0x8E7164)

    static let primary = Color(hex: 0xA04100)
    static let onPrimary = Color.white
    static let primaryContainer = Color(hex: 0xFF6B00)
    static let onPrimaryContainer = Color(hex: 0x572000)

    static let secondary = Color(hex: 0x0001C0)
    static let onSecondary = Color.white
    static let secondaryContainer = Color(hex: 0x080CFF)
    static let secondaryFixed = Color(hex: 0xE0E0FF)

    static let tertiary = Color(hex: 0x506600)
    static let onTertiary = Color.white
    static let tertiaryContainer = Color(hex: 0x83A500)
    static let onTertiaryContainer = Color(hex: 0x293600)
    static let tertiaryFixed = Color(hex: 0xC3F400)

    static let error = Color(hex: 0xBA1A1A)
    static let errorContainer = Color(hex: 0xFFDAD6)

    /// Progress fill from DESIGN.md component notes
    static let progressFill = Color(hex: 0xCCFF00)
}

enum KTSpacing {
    static let base: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 16
    static let md: CGFloat = 24
    static let lg: CGFloat = 40
    static let borderThick: CGFloat = 3
    static let borderThin: CGFloat = 1
    static let shadowOffset: CGFloat = 4
    static let shadowOffsetLarge: CGFloat = 8
    static let headerHeight: CGFloat = 80
    static let bottomNavHeight: CGFloat = 64
    static let sideNavWidth: CGFloat = 256
}

enum KTTypography {
    /// Headings: heavy sans (Hanken Grotesk in design; system black fallback)
    static func display() -> Font {
        .system(size: 48, weight: .black, design: .default)
    }

    static func headlineLG() -> Font {
        .system(size: 32, weight: .heavy, design: .default)
    }

    static func headlineLGMobile() -> Font {
        .system(size: 24, weight: .heavy, design: .default)
    }

    static func bodyMD() -> Font {
        .system(size: 16, weight: .medium, design: .default)
    }

    /// Data layer: Space Mono in design; monospaced fallback
    static func technicalMD() -> Font {
        .system(size: 14, weight: .regular, design: .monospaced)
    }

    static func technicalSM() -> Font {
        .system(size: 12, weight: .regular, design: .monospaced)
    }

    static func labelCaps() -> Font {
        .system(size: 11, weight: .bold, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
