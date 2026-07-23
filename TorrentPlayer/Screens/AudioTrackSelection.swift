//
//  AudioTrackSelection.swift
//  TorrentPlayer
//
//  Labels and options for in-player audio track switching (AVPlayer / SwiftVLC).
//

import Foundation

struct AudioTrackOption: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    var isSelected: Bool
}

enum AudioTrackSelection {
    /// Human-readable row for a track: `"NAME (LANG)"`, name alone, or `AUDIO N`.
    static func label(
        name: String?,
        language: String?,
        description: String? = nil,
        fallbackIndex: Int
    ) -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedLang = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedDesc = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let base: String
        if !trimmedName.isEmpty {
            base = trimmedName
        } else if !trimmedDesc.isEmpty {
            base = trimmedDesc
        } else {
            base = "AUDIO \(max(1, fallbackIndex))"
        }

        if !trimmedLang.isEmpty, !baseAlreadyIncludesLanguage(base, language: trimmedLang) {
            return "\(base) (\(trimmedLang.uppercased()))"
        }
        return base
    }

    /// True when `language` already appears as its own token (or `(LANG)`), not as a
    /// substring of a longer word — so `"English"` + `"eng"` still becomes `"English (ENG)"`.
    private static func baseAlreadyIncludesLanguage(_ base: String, language: String) -> Bool {
        if base.range(of: "(\(language))", options: .caseInsensitive) != nil {
            return true
        }
        let tokens = base.split { !$0.isLetter && !$0.isNumber }.map { String($0).lowercased() }
        return tokens.contains(language.lowercased())
    }

    static func shouldShowPicker(trackCount: Int) -> Bool {
        trackCount > 1
    }
}
