//
//  KTComponents.swift
//  TorrentPlayer
//
//  Shared neo-brutalist UI primitives for Kinetic Torrent screens.
//

import SwiftUI

struct HardShadow: ViewModifier {
    var offset: CGFloat = KTSpacing.shadowOffset
    var color: Color = KTColor.onBackground

    func body(content: Content) -> some View {
        if offset == 0 {
            content
        } else {
            // Draw the block shadow outside the view bounds. Do not add
            // trailing/bottom layout padding — that inflated ScrollView/ZStack
            // ideal width and clipped leading content on narrow phones.
            // Parent screens already use KTSpacing.md (≥ shadow) padding.
            content
                .background(alignment: .topLeading) {
                    Rectangle()
                        .fill(color)
                        .offset(x: offset, y: offset)
                }
        }
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
        let shadow = largeShadow ? KTSpacing.shadowOffsetLarge : KTSpacing.shadowOffset
        // Shadow sized to the label (not a free Rectangle in ZStack — that ate leftover height).
        // Fixed outer padding: moving the control on press cancels macOS mouse-up.
        configuration.label
            .offset(
                x: configuration.isPressed ? shadow : 0,
                y: configuration.isPressed ? shadow : 0
            )
            .background(alignment: .topLeading) {
                if !configuration.isPressed {
                    Rectangle()
                        .fill(KTColor.onBackground)
                        .offset(x: shadow, y: shadow)
                }
            }
            .padding(.trailing, shadow)
            .padding(.bottom, shadow)
            .contentShape(Rectangle())
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
            .lineLimit(2)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .overlay(Rectangle().strokeBorder(KTColor.onBackground, lineWidth: 1))
    }
}

#if os(iOS)
import UIKit

struct MagnetURIEditor: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = .clear
        textView.textColor = UIColor(KTColor.onBackground)
        textView.tintColor = UIColor(KTColor.onBackground)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.dataDetectorTypes = []
        textView.linkTextAttributes = [:]
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainerInset = UIEdgeInsets(top: 36, left: 16, bottom: 16, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.layoutManager.allowsNonContiguousLayout = false
        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}
#else
import AppKit

struct MagnetURIEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor(KTColor.onBackground)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 36)
        textView.string = text
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        scroll.documentView = textView
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text = textView.string
        }
    }
}
#endif

struct AppHeaderBar: View {
    @State private var showSettings = false

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
                showSettings = true
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
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, KTSpacing.md)
        .frame(height: KTSpacing.headerHeight)
        .background(KTColor.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(KTColor.onBackground)
                .frame(height: KTSpacing.borderThick)
        }
        // Header is full-bleed; reserve shadow strip so it is not clipped by the screen edge.
        .hardShadow()
        .padding(.trailing, KTSpacing.shadowOffset)
        .padding(.bottom, KTSpacing.shadowOffset)
        .zIndex(10)
        .sheet(isPresented: $showSettings) {
            SettingsSheetView()
        }
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
