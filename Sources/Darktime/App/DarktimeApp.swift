import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

@MainActor
enum DarktimeAppStorage {
    static var delegate: DarktimeAppDelegate?
}

@MainActor
func launchDarktimeAppUI() {
    let app = NSApplication.shared
    let delegate = DarktimeAppDelegate()
    DarktimeAppStorage.delegate = delegate

    app.setActivationPolicy(.regular)
    app.delegate = delegate
    configureApplicationMenu()
    app.activate(ignoringOtherApps: true)
    app.run()
}

