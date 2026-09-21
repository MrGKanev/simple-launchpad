import SwiftUI
import AppKit

struct AppIconView: View {
    let app: AppInfo

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path))
                .resizable()
                .frame(width: 64, height: 64)
            Text(app.name)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(width: 90, height: 100)
    }
}
