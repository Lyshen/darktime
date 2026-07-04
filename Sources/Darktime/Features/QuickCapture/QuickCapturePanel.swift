import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct QuickCapturePanel: View {
    @ObservedObject var model: DashboardModel
    let onClose: () -> Void
    @State private var message: String?
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    private var canSave: Bool {
        !model.quickCaptureDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Capture it.", text: $model.quickCaptureDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular, design: .default))
                .foregroundStyle(DTColor.text)
                .lineLimit(1)
                .focused($isInputFocused)
                .onSubmit {
                    save()
                }
                .frame(height: 46)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 4)

            HStack(alignment: .center, spacing: 10) {
                statusView

                Spacer()

                if canSave {
                    Button {
                        model.clearQuickCaptureDraft()
                        errorMessage = nil
                        message = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DTColor.dimmed)
                    .help("Clear draft")
                }

                Button {
                    save()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 32, height: 32)
                        .background(canSave ? DTColor.text : DTColor.dimmed.opacity(0.45))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .help("Capture")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 9)
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(DTColor.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DTColor.inputBorder, lineWidth: 1.25)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear {
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
        .onExitCommand {
            closeKeepingDraft()
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(DTColor.red)
        } else if let message {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(DTColor.green)
        } else {
            HStack(spacing: 6) {
                Text("Esc")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(DTColor.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DTColor.row)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(DTColor.line, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text("close")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
            }
        }
    }

    private func closeKeepingDraft() {
        onClose()
    }

    private func save() {
        let trimmed = model.quickCaptureDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        if model.capture(text: trimmed, source: "quick_capture") {
            model.clearQuickCaptureDraft()
            errorMessage = nil
            message = "Captured"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                onClose()
            }
        } else {
            errorMessage = "Could not capture"
        }
    }
}
