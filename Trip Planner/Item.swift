//
//  Item.swift
//  Trip Planner
//
//  Created by Lukas Sonnabend on 03.08.2026.
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
