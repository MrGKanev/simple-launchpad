import SwiftUI
import UniformTypeIdentifiers

struct PageView: View {
    @Binding var items: [LaunchpadItem]
    let onSelect: (AppInfo) -> Void
    let onMergeIntoFolder: (Int, Int) -> Void

    // ponytail: manual `SwiftUI.State<Value>` wiring instead of the `@State`
    // attribute — see the comment in LaunchpadView.swift for why (this SDK's
    // `@State` macro plugin isn't available under Xcode Command Line Tools).
    private var selectedFolderState = SwiftUI.State<FolderInfo?>(wrappedValue: nil)
    private var selectedFolder: FolderInfo? {
        get { selectedFolderState.wrappedValue }
        nonmutating set { selectedFolderState.wrappedValue = newValue }
    }

    private let columns = Array(repeating: GridItem(.fixed(90), spacing: 24), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 24) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                itemView(for: item, at: index)
                    .onDrag { NSItemProvider(object: String(index) as NSString) }
                    .onDrop(of: [.text], delegate: ItemDropDelegate(
                        targetIndex: index,
                        items: $items,
                        onMergeIntoFolder: onMergeIntoFolder
                    ))
            }
        }
        .padding(40)
        .sheet(item: selectedFolderState.projectedValue) { folder in
            FolderView(folder: folder, onSelect: onSelect)
        }
    }

    @ViewBuilder
    private func itemView(for item: LaunchpadItem, at index: Int) -> some View {
        switch item {
        case .app(let app):
            AppIconView(app: app)
                .onTapGesture { onSelect(app) }
        case .folder(let folder):
            FolderIconView(folder: folder)
                .onTapGesture { selectedFolder = folder }
        }
    }
}

// ponytail: hover state is a static dictionary keyed by target index, not per-drag-session
// state, because DropDelegate structs are recreated on every render. Fine for a single-user,
// single-drag-at-a-time grid; would need real per-session state if concurrent drags were possible.
private struct ItemDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var items: [LaunchpadItem]
    let onMergeIntoFolder: (Int, Int) -> Void

    private static let mergeHoldThreshold: TimeInterval = 0.6
    private static var hoverStartedAt: [Int: Date] = [:]

    func dropEntered(info: DropInfo) {
        Self.hoverStartedAt[targetIndex] = Date()
    }

    func performDrop(info: DropInfo) -> Bool {
        let hoverDuration = Self.hoverStartedAt[targetIndex].map { Date().timeIntervalSince($0) } ?? 0
        Self.hoverStartedAt[targetIndex] = nil

        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let string = reading as? String, let sourceIndex = Int(string) else { return }
            DispatchQueue.main.async {
                guard sourceIndex != targetIndex,
                      items.indices.contains(sourceIndex),
                      items.indices.contains(targetIndex) else { return }

                let isMergeable: Bool = {
                    if case .app = items[sourceIndex] {
                        if case .app = items[targetIndex] { return true }
                        if case .folder = items[targetIndex] { return true }
                    }
                    return false
                }()

                if hoverDuration >= Self.mergeHoldThreshold && isMergeable {
                    onMergeIntoFolder(sourceIndex, targetIndex)
                } else {
                    let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
                    items.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
                }
            }
        }
        return true
    }
}
