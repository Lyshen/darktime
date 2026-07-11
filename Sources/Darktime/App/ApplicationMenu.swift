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
        action: #selector(DarktimeAppDelegate.showQuickCaptureFromMenu(_:)),
        keyEquivalent: "n"
    )
    appMenu.addItem(
        withTitle: "Shortcut Capture",
        action: #selector(DarktimeAppDelegate.showShortcutCaptureFromMenu(_:)),
        keyEquivalent: ""
    )
    appMenu.addItem(
        withTitle: "Calendar",
        action: #selector(DarktimeAppDelegate.showCalendarFromMenu(_:)),
        keyEquivalent: "k"
    )
    appMenu.addItem(
        withTitle: "Dropped",
        action: #selector(DarktimeAppDelegate.showDroppedFromMenu(_:)),
        keyEquivalent: ""
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
