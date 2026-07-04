import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct InboxWorkspace: View {
    @ObservedObject var model: DashboardModel
    @State private var isClearing = false

    var body: some View {
        VStack(spacing: 0) {
            if isClearing {
                ClearFlowWorkspace(model: model) {
                    isClearing = false
                }
            } else {
                InboxListWorkspace(model: model) {
                    isClearing = true
                }
            }
        }
        .background(DTColor.workspace)
    }
}
