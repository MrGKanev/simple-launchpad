import SwiftUI

struct FolderView: View {
    let folder: FolderInfo
    let onSelect: (AppInfo) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.fixed(90), spacing: 24), count: 5)

    var body: some View {
        VStack(spacing: 20) {
            Text(folder.name)
                .font(.title2)
                .foregroundColor(.white)
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(folder.apps, id: \.bundleIdentifier) { app in
                    AppIconView(app: app)
                        .onTapGesture {
                            onSelect(app)
                            dismiss()
                        }
                }
            }
        }
        .padding(40)
        .frame(minWidth: 500, minHeight: 400)
        .background(Color.black.opacity(0.85))
    }
}

extension FolderInfo: Identifiable {
    var id: String { name + apps.map(\.bundleIdentifier).joined() }
}
