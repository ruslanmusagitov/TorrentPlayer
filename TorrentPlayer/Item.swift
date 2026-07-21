//
//  Item.swift
//  TorrentPlayer
//
//  Created by Ruslan on 21.07.2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
