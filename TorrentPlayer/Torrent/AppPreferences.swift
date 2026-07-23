//
//  AppPreferences.swift
//  TorrentPlayer
//
//  Persisted user preferences (UserDefaults).
//

import Foundation

enum AppPreferences {
    private static let seedingEnabledKey = "torrentPlayer.seedingEnabled"

    /// When true, upload completed pieces to peers. Default: off.
    static var seedingEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: seedingEnabledKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: seedingEnabledKey)
        }
    }
}
