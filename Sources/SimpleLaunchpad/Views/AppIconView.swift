import SwiftUI
import AppKit

struct AppIconView: View {
    let app: AppInfo
    var metrics: IconGridMetrics = .fixed
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path))
                    .resizable()
                    .frame(width: metrics.imageSize, height: metrics.imageSize)
                Text(app.name)
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
