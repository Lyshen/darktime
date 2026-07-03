import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct RootboxWorkspace: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        MatterWorkspace(
            systemImage: "tree.fill",
            title: "Rootbox",
            detail: "Matters worth keeping and returning to.",
            matters: model.rootboxMatters,
            emptyTitle: "Rootbox is empty",
            emptyDetail: "Clear the inbox and keep only the few things worth returning to.",
            model: model
        )
    }
}


