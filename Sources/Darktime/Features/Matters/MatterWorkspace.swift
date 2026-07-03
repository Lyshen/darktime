import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct MatterWorkspace: View {
    let systemImage: String
    let title: String
    let detail: String
    let matters: [MatterSnapshot]
    let emptyTitle: String
    let emptyDetail: String
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTopBar(systemImage: systemImage, title: title, detail: detail)
            Divider().overlay(DTColor.line.opacity(0.7))

            MatterList(
                matters: matters,
                emptyTitle: emptyTitle,
                emptyDetail: emptyDetail,
                model: model
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DTColor.workspace)
    }
}


