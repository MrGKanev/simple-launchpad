import SwiftUI
import AppKit

struct FolderIconView: View {
    let folder: FolderInfo

    private let columns = [GridItem(.fixed(26)), GridItem(.fixed(26))]

    var body: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(folder.apps.prefix(4)), id: \.bundleIdentifier) { app in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path))
                        .resizable()
                        .frame(width: 24, height: 24)
                }
            }
            .padding(6)
            .frame(width: 64, height: 64)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.15)))
            Text(folder.name)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(width: 90, height: 100)
    }
}
