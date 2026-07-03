import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct QuickCaptureTextInput: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> QuickCaptureTextField {
        let textField = QuickCaptureTextField()
        textField.delegate = context.coordinator
        textField.font = NSFont.systemFont(ofSize: 15)
        textField.textColor = NSColor.labelColor
        textField.stringValue = text
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.onSubmit = onSubmit
        textField.onCancel = onCancel
        textField.normalizeEditorStyle()
        return textField
    }

    func updateNSView(_ nsView: QuickCaptureTextField, context: Context) {
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onCancel = onCancel
        if !nsView.isComposingText, nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.onSubmit = onSubmit
        nsView.onCancel = onCancel
        nsView.placeholderString = placeholder
        nsView.textColor = NSColor.labelColor
        if !nsView.isComposingText {
            nsView.normalizeEditorStyle()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onSubmit: () -> Void
        var onCancel: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onCancel: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
            self.onCancel = onCancel
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let textField = notification.object as? QuickCaptureTextField else {
                return
            }
            textField.normalizeEditorStyle()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? QuickCaptureTextField else {
                return
            }
            guard !textField.isComposingText else {
                return
            }
            textField.normalizeEditorStyle()
            text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? QuickCaptureTextField else {
                return
            }
            text = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                guard !textView.hasMarkedText() else {
                    return false
                }
                onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                guard !textView.hasMarkedText() else {
                    return false
                }
                onCancel()
                return true
            default:
                if !textView.hasMarkedText() {
                    textView.textColor = NSColor.labelColor
                    textView.insertionPointColor = NSColor.labelColor
                }
                return false
            }
        }
    }
}

final class QuickCaptureTextField: NSTextField {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        normalizeEditorStyle()
        return result
    }

    var isComposingText: Bool {
        (currentEditor() as? NSTextView)?.hasMarkedText() == true
    }

    func normalizeEditorStyle() {
        let textFont = font ?? NSFont.systemFont(ofSize: 15)
        let textColor = NSColor.labelColor
        font = textFont
        self.textColor = textColor

        guard let editor = currentEditor() as? NSTextView else {
            return
        }
        guard !editor.hasMarkedText() else {
            return
        }
        editor.textColor = textColor
        editor.insertionPointColor = textColor
        editor.typingAttributes = [
            .font: textFont,
            .foregroundColor: textColor
        ]
    }
}

extension NSView {
    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        if let view = self as? T {
            return view
        }
        for subview in subviews {
            if let match = subview.firstSubview(of: type) {
                return match
            }
        }
        return nil
    }
}

