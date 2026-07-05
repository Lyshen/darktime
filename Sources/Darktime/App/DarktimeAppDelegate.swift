import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

@MainActor
final class DarktimeAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var quickCaptureWindow: NSPanel?
    private var model: DashboardModel?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = DashboardModel()
        self.model = model
        buildWindow(model: model)
        registerQuickCaptureHotKey()
        model.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    @objc func showQuickCaptureFromMenu(_ sender: Any?) {
        showQuickCapture()
    }

    @objc func showCalendarFromMenu(_ sender: Any?) {
        model?.selectedSection = .calendar
        showMainWindow()
    }

    @objc func showShortcutCaptureFromMenu(_ sender: Any?) {
        model?.selectedSection = .shortcutCapture
        showMainWindow()
    }

    @objc func showDroppedFromMenu(_ sender: Any?) {
        model?.selectedSection = .dropped
        showMainWindow()
    }

    private func buildWindow(model: DashboardModel) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 840)
        let contentRect = visibleFrame.insetBy(dx: max(24, visibleFrame.width * 0.035), dy: max(24, visibleFrame.height * 0.05))
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Darktime"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .white
        window.minSize = NSSize(width: 1060, height: 680)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: DarktimeDashboard(model: model))

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    private func showMainWindow() {
        if window == nil, let model {
            buildWindow(model: model)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func registerQuickCaptureHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr, hotKeyID.id == 1 else {
                    return noErr
                }

                let appDelegate = Unmanaged<DarktimeAppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    appDelegate.showQuickCapture()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: fourCharCode("DTQC"), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func showQuickCapture() {
        guard let model else {
            return
        }

        let panel = quickCaptureWindow ?? makeQuickCaptureWindow()
        quickCaptureWindow = panel
        panel.delegate = self
        let hostingView = ClearHostingView(
            rootView: QuickCapturePanel(model: model) { [weak self] in
                self?.quickCaptureWindow?.orderOut(nil)
            }
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        if let screen = NSScreen.main {
            let size = panel.frame.size
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height - 96
            ))
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            panel.makeKey()
        }
    }

    private func makeQuickCaptureWindow() -> NSPanel {
        let panel = QuickCaptureWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 112),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.appearance = NSAppearance(named: .aqua)
        return panel
    }
}

extension DarktimeAppDelegate: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        guard
            let panel = notification.object as? NSPanel,
            panel == quickCaptureWindow
        else {
            return
        }
        panel.orderOut(nil)
    }
}
