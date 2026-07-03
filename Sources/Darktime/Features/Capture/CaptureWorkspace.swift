import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct CaptureWorkspace: View {
    @ObservedObject var model: DashboardModel
    @State private var draft = ""
    @State private var savedMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            DTColor.workspace

            VStack(spacing: 38) {
                Text("What matters right now?")
                    .font(.system(size: 30, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.text)

                VStack(spacing: 0) {
                    TextField("Capture it.", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .foregroundStyle(DTColor.text)
                        .lineLimit(1...4)
                        .focused($focused)
                        .onSubmit(save)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                        .frame(minHeight: 52, alignment: .topLeading)

                    HStack(alignment: .center, spacing: 10) {
                        if let savedMessage {
                            Label(savedMessage, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .medium, design: .default))
                                .foregroundStyle(DTColor.green)
                                .transition(.opacity)
                        } else {
                            Label("Inbox", systemImage: "tray")
                                .font(.system(size: 12, weight: .medium, design: .default))
                                .foregroundStyle(DTColor.dimmed)
                        }

                        Spacer()

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
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(!canSave)
                        .help("Capture")
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                .frame(maxWidth: 760, minHeight: 104)
                .background(DTColor.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(DTColor.inputBorder, lineWidth: 1.25)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Color.black.opacity(0.08), radius: 22, x: 0, y: 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 56)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focused = true
            }
        }
    }

    private var canSave: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        model.capture(text: trimmed, source: "manual", revealInbox: false)
        draft = ""

        withAnimation(.easeOut(duration: 0.18)) {
            savedMessage = "Captured to Inbox"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.18)) {
                savedMessage = nil
            }
        }
    }
}


