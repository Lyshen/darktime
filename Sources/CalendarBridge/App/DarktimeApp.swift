import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

@MainActor
enum CalendarAppStorage {
    static var delegate: CalendarAppDelegate?
}

@MainActor
func launchCalendarAppUI() {
    let app = NSApplication.shared
    let delegate = CalendarAppDelegate()
    CalendarAppStorage.delegate = delegate

    app.setActivationPolicy(.regular)
    app.delegate = delegate
    configureApplicationMenu()
    app.activate(ignoringOtherApps: true)
    app.run()
}

