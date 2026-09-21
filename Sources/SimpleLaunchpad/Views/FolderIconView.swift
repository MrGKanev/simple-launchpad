import SwiftUI
import AppKit

struct FolderIconView: View {
    let folder: FolderInfo
    var metrics: IconGridMetrics = .fixed
    let onTap: () -> Void

    private var miniIconSize: CGFloat { max(12, (metrics.imageSize - 16 - 3) / 2) }
    private var columns: [GridItem] { [GridItem(.fixed(miniIconSize)), GridItem(.fixed(miniIconSize))] }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(Array(folder.apps.prefix(4)), id: \.bundleIdentifier) { app in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path))
                            .resizable()
                            .frame(width: miniIconSize, height: miniIconSize)
                    }
                }
                .padding(8)
                .frame(width: metrics.imageSize, height: metrics.imageSize)
                .background(RoundedRectangle(cornerRadius: metrics.imageSize * 0.19).fill(Color.white.opacity(0.15)))
                Text(folder.name)
                    .font(metrics.font)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(width: metrics.cellWidth, height: metrics.cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(IconButtonStyle())
    }
}
