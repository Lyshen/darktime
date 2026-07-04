import SwiftUI

struct QuietHeaderButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(DTColor.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minWidth: 50, minHeight: 25)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering in
            isHovered = hovering && isEnabled
        }
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return Color.black.opacity(0.02)
        }
        return Color.black.opacity(isHovered ? 0.07 : 0.045)
    }

    private var borderColor: Color {
        if !isEnabled {
            return Color.black.opacity(0.04)
        }
        return Color.black.opacity(isHovered ? 0.13 : 0.08)
    }
}
