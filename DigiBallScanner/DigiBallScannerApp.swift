//
//  DigiBallScannerApp.swift
//  DigiBallScanner
//
//  Created by Nathan Rhoades on 4/25/25.
//

import SwiftUI

class GlobalSettings: ObservableObject {
    @Published var lastShotNumber: UInt8 = 255
    func updateShotNumber(value: UInt8) {
        lastShotNumber = value
    }
}

@main
struct DigiBallScannerApp: App {
    var settings = GlobalSettings()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
    }
}
