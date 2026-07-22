//
//  PlaybackFormatting.swift
//  TorrentPlayer
//
//  Task #8: clock / fraction helpers for streaming player progress.
//

import Foundation

enum PlaybackFormatting {
    /// `HH:MM:SS`, or `--:--:--` when unknown.
    static func clock(seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--:--" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    static func fraction(current: TimeInterval, duration: TimeInterval) -> Double {
        guard duration.isFinite, duration > 0, current.isFinite else { return 0 }
        return min(1, max(0, current / duration))
    }

    /// Download/buffer bar width as a 0…1 fraction.
    static func downloadFraction(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(1, max(0, progress))
    }

    static func etaClock(
        progress: Double,
        rateBytesPerSecond: Double,
        totalBytes: Int64
    ) -> String {
        let clamped = downloadFraction(progress)
        if clamped >= 1 { return "00:00:00" }
        guard rateBytesPerSecond > 0, totalBytes > 0 else { return "--:--:--" }
        let remaining = Double(totalBytes) * (1 - clamped)
        return clock(seconds: remaining / rateBytesPerSecond)
    }

    /// Single-line rate for stats grids, e.g. `1.2 MB/s`, or `—` when idle.
    static func formatRate(_ bytesPerSecond: Double) -> String {
        let parts = rateParts(bytesPerSecond)
        guard parts.value != "—" else { return "—" }
        return "\(parts.value) \(parts.unit)/s"
    }

    /// Value + unit for Load Magnet cards (`88.2` + `MB/S`).
    static func rateParts(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        guard bytesPerSecond > 0, bytesPerSecond.isFinite else {
            return ("—", "MB/S")
        }
        if bytesPerSecond >= 1_000_000_000 {
            return (String(format: "%.1f", bytesPerSecond / 1_000_000_000), "GB/S")
        }
        if bytesPerSecond >= 1_000_000 {
            return (String(format: "%.1f", bytesPerSecond / 1_000_000), "MB/S")
        }
        if bytesPerSecond >= 1_000 {
            return (String(format: "%.1f", bytesPerSecond / 1_000), "KB/S")
        }
        return (String(format: "%.0f", bytesPerSecond), "B/S")
    }
}
