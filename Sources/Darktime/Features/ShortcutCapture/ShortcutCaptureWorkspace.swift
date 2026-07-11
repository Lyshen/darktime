import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

private enum ShortcutCaptureConfig {
    static let shortcutName = "Darktime"
    static let bundledInstallURLString = "https://www.icloud.com/shortcuts/aee92538cdeb4b018e6c7989b959253c"
    static let userDefaultsInstallURLKey = "darktime.shortcutInstallURL"
    static let environmentInstallURLKey = "DARKTIME_SHORTCUT_INSTALL_URL"

    static var installURL: URL? {
        let candidates = [
            UserDefaults.standard.string(forKey: userDefaultsInstallURLKey),
            ProcessInfo.processInfo.environment[environmentInstallURLKey],
            bundledInstallURLString
        ]

        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty, let url = URL(string: trimmed) {
                return url
            }
        }

        return nil
    }
}

struct ShortcutCaptureWorkspace: View {
    @ObservedObject var model: DashboardModel
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTopBar(
                systemImage: "iphone",
                title: "Shortcut Capture",
                detail: "iPhone and Siri capture into Inbox"
            )
            Divider().overlay(DTColor.line.opacity(0.7))

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ShortcutIntro()

                    ShortcutInstallSection(model: model)

                    ShortcutTroubleshootingSection(model: model, message: message) {
                        if model.createShortcutTestCapture() {
                            message = "Test capture added to Inbox"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                message = nil
                            }
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 42)
                .padding(.top, 30)
                .padding(.bottom, 40)
            }
        }
        .background(DTColor.workspace)
        .onAppear {
            model.prepareShortcutCaptureFolders()
        }
    }
}

private struct ShortcutIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set up iPhone capture.")
                .font(.system(size: 21, weight: .regular, design: .default))
                .foregroundStyle(DTColor.text)
            Text("Scan the Shortcut, run it once, and allow Apple's prompts. New captures will appear in Inbox after iCloud syncs.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ShortcutTroubleshootingSection: View {
    @ObservedObject var model: DashboardModel
    let message: String?
    let onCreateTest: () -> Void
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ShortcutInfoRow(
                    title: "Drop-off",
                    value: "iCloud Drive/Shortcuts/Darktime/Inbox"
                )
                ShortcutInfoRow(
                    title: "Pending",
                    value: "\(model.shortcutPendingCount)"
                )
                ShortcutInfoRow(
                    title: "Failed",
                    value: "\(model.shortcutFailedCount)"
                )
                ShortcutInfoRow(
                    title: "Mac path",
                    value: model.shortcutInboxPath
                )

                HStack(spacing: 12) {
                    QuietHeaderButton("Open Inbox") {
                        model.openShortcutInboxFolder()
                    }
                    QuietHeaderButton("Open Failed") {
                        model.openShortcutFailedFolder()
                    }
                    QuietHeaderButton("Create Mac Test") {
                        onCreateTest()
                    }
                    if let message {
                        Text(message)
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(DTColor.green)
                    }
                    Spacer()
                }
                .padding(.top, 14)
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 12, weight: .regular))
                Text("Troubleshooting")
                    .font(.system(size: 13, weight: .regular, design: .default))
                if model.shortcutFailedCount > 0 {
                    Text("\(model.shortcutFailedCount) failed")
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(DTColor.red)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(DTColor.red.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(DTColor.muted)
        }
        .tint(DTColor.muted)
    }
}

private struct ShortcutInstallSection: View {
    @ObservedObject var model: DashboardModel
    @State private var copied = false
    @State private var activeInstallURL = ShortcutCaptureConfig.installURL

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let installURL = activeInstallURL {
                HStack(alignment: .top, spacing: 22) {
                    QRCodeView(text: installURL.absoluteString)
                        .frame(width: 148, height: 148)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 14) {
                        ShortcutSetupStep(
                            number: 1,
                            title: "Scan and add",
                            detail: "Open this QR code with iPhone and tap Add Shortcut."
                        )
                        ShortcutSetupStep(
                            number: 2,
                            title: "Run it once",
                            detail: "Allow Shortcuts to save files when Apple asks."
                        )
                        ShortcutSetupStep(
                            number: 3,
                            title: "Capture from iPhone",
                            detail: "Tap it in Shortcuts, add it to Home Screen, or say: Hey Siri, run \(ShortcutCaptureConfig.shortcutName)."
                        )

                        HStack(spacing: 12) {
                            QuietHeaderButton("Open Link") {
                                NSWorkspace.shared.open(installURL)
                            }
                            QuietHeaderButton(copied ? "Copied" : "Copy Link") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(installURL.absoluteString, forType: .string)
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                    copied = false
                                }
                            }
                        }

                        Text("Darktime is listening. \(model.inboxMatters.count) item\(model.inboxMatters.count == 1 ? "" : "s") in Inbox.")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(DTColor.dimmed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
            } else {
                MissingInstallLinkView()
            }
        }
    }
}

private struct MissingInstallLinkView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shortcut link is not configured.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(DTColor.text)
            Text("Add a shared Apple Shortcut link to the app build to show a QR code here.")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

private struct ShortcutSetupStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Text("\(number)")
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(DTColor.dimmed)
                .frame(width: 18, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.text)
                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = makeQRCodeImage(from: text) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.025))
        }
    }

    private func makeQRCodeImage(from text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard
            let outputImage = filter.outputImage,
            let cgImage = CIContext().createCGImage(outputImage, from: outputImage.extent)
        else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: 256, height: 256))
    }
}

private struct ShortcutInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text(title)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.muted)
                    .frame(width: 88, alignment: .leading)
                Text(value)
                    .font(.system(size: 12, weight: .regular, design: value.contains("/") ? .monospaced : .default))
                    .foregroundStyle(DTColor.text)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color.black.opacity(0.055))
                .frame(height: 1)
        }
    }
}
