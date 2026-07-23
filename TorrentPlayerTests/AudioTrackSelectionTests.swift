//
//  AudioTrackSelectionTests.swift
//  TorrentPlayerTests
//

import Testing
@testable import TorrentPlayer

struct AudioTrackSelectionTests {
    @Test func labelUsesNameAndLanguage() {
        #expect(
            AudioTrackSelection.label(
                name: "English",
                language: "eng",
                fallbackIndex: 1
            ) == "English (ENG)"
        )
    }

    @Test func labelSkipsRedundantLanguageInName() {
        #expect(
            AudioTrackSelection.label(
                name: "Track eng",
                language: "eng",
                fallbackIndex: 1
            ) == "Track eng"
        )
    }

    @Test func labelFallsBackToDescriptionThenIndex() {
        #expect(
            AudioTrackSelection.label(
                name: "  ",
                language: nil,
                description: "Commentary",
                fallbackIndex: 2
            ) == "Commentary"
        )
        #expect(
            AudioTrackSelection.label(
                name: nil,
                language: "ja",
                description: nil,
                fallbackIndex: 3
            ) == "AUDIO 3 (JA)"
        )
    }

    @Test func shouldShowPickerOnlyWithMultipleTracks() {
        #expect(AudioTrackSelection.shouldShowPicker(trackCount: 0) == false)
        #expect(AudioTrackSelection.shouldShowPicker(trackCount: 1) == false)
        #expect(AudioTrackSelection.shouldShowPicker(trackCount: 2) == true)
    }
}
