import SwiftUI

struct MatterMetaLine: View {
    let createdAt: String
    let source: String

    var body: some View {
        Text("\(formatRelative(createdAt)) · \(formatMatterSource(source))")
            .font(.system(size: 11, weight: .regular, design: .default))
            .foregroundStyle(DTColor.dimmed)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
