//
//  PlaybackFormattingTests.swift
//  TorrentPlayerTests
//

import Testing
@testable import TorrentPlayer

struct PlaybackFormattingTests {
    @Test func clockFormatsKnownDurations() {
        #expect(PlaybackFormatting.clock(seconds: 0) == "00:00:00")
        #expect(PlaybackFormatting.clock(seconds: 65) == "00:01:05")
        #expect(PlaybackFormatting.clock(seconds: 3723) == "01:02:03")
    }

    @Test func clockReturnsPlaceholderForUnknown() {
        #expect(PlaybackFormatting.clock(seconds: nil) == "--:--:--")
        #expect(PlaybackFormatting.clock(seconds: .nan) == "--:--:--")
        #expect(PlaybackFormatting.clock(seconds: -1) == "--:--:--")
    }

    @Test func fractionClampsAndGuards() {
        #expect(PlaybackFormatting.fraction(current: 30, duration: 100) == 0.3)
        #expect(PlaybackFormatting.fraction(current: 150, duration: 100) == 1)
        #expect(PlaybackFormatting.fraction(current: -5, duration: 100) == 0)
        #expect(PlaybackFormatting.fraction(current: 10, duration: 0) == 0)
        #expect(PlaybackFormatting.fraction(current: 10, duration: .infinity) == 0)
    }

    @Test func downloadFractionClamps() {
        #expect(PlaybackFormatting.downloadFraction(0.42) == 0.42)
        #expect(PlaybackFormatting.downloadFraction(1.5) == 1)
        #expect(PlaybackFormatting.downloadFraction(-0.2) == 0)
        #expect(PlaybackFormatting.downloadFraction(.nan) == 0)
    }

    @Test func etaClockUsesRateAndProgress() {
        #expect(
            PlaybackFormatting.etaClock(
                progress: 0.5,
                rateBytesPerSecond: 1_000_000,
                totalBytes: 2_000_000
            ) == "00:00:01"
        )
        #expect(
            PlaybackFormatting.etaClock(
                progress: 1,
                rateBytesPerSecond: 0,
                totalBytes: 100
            ) == "00:00:00"
        )
        #expect(
            PlaybackFormatting.etaClock(
                progress: 0.2,
                rateBytesPerSecond: 0,
                totalBytes: 100
            ) == "--:--:--"
        )
    }
}
