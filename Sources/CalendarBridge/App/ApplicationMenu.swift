import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

@MainActor
func configureApplicationMenu() {
    let menu = NSMenu()
    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()

    appMenu.addItem(
        withTitle: "Quick Capture",
        action: #selector(CalendarAppDelegate.showQuickCaptureFromMenu(_:)),
        keyEquivalent: "n"
    )
    appMenu.addItem(
        withTitle: "Calendar",
        action: #selector(CalendarAppDelegate.showCalendarFromMenu(_:)),
        keyEquivalent: "k"
    )
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(
        withTitle: "Quit Darktime",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )
    appMenuItem.submenu = appMenu
    menu.addItem(appMenuItem)

    NSApplication.shared.mainMenu = menu
}

