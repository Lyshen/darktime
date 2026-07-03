import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct WorkspaceTitle: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DTColor.cyan)
                .frame(width: 34, height: 34)
                .background(DTColor.cyan.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(DTColor.muted)
            }
            Spacer()
        }
    }
}


