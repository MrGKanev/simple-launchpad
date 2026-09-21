import SwiftUI
import UniformTypeIdentifiers

struct PageView: View {
    @Binding var items: [LaunchpadItem]
    let metrics: IconGridMetrics
    let selectedIndex: Int
    // Lives in `LaunchpadStore` (not view-local state here) so a
    // keyboard-selected folder can also be opened from
    // `OverlayWindowController`'s Return-key handling, outside SwiftUI.
    @Binding var openFolder: FolderInfo?
    let onSelect: (AppInfo) -> Void
    // Routed all the way to `LaunchpadStore` (rather than mutating `items`
    // locally) so removal/uninstall can prune an emptied page and keep the
    // open folder sheet in sync in one place — see
    // `LaunchpadStore.removeApp`/`uninstallApp`.
    let onRemoveApp: (AppInfo) -> Void
    let onUninstallApp: (AppInfo) -> Void
    let onRenameFolder: (FolderInfo, String) -> Void
    let onEditingFolderNameChanged: (Bool) -> Void
    let onMergeIntoFolder: (Int, Int) -> Void
    // Cmd/Shift-click multi-select — see `AppIconView` and
    // `LaunchpadStore.selectedBundleIdentifiers`.
    let selectedBundleIdentifiers: Set<String>
    let onToggleSelectApp: (AppInfo) -> Void
    let onBulkRemove: () -> Void
    let onBulkUninstall: () -> Void
    // Dragging one icon out of an active multi-selection (2+ apps) and
    // dropping it on a target moves *all* selected apps into that target —
    // see `LaunchpadStore.mergeSelectedApps`.
    let onBulkMergeIntoTarget: (LaunchpadItem) -> Void
    // Holding a drag over the left/right edge briefly flips the page, so a
    // dropped icon can be moved onto a page other than the current one.
    let onRequestPageChange: (Int) -> Void

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(metrics.cellWidth), spacing: metrics.spacing), count: metrics.columns)
    }

    var body: some View {
        ZStack {
            LazyVGrid(columns: columns, spacing: metrics.spacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    itemView(for: item, at: index)
                        .onDrag {
                            // Dragging a member of an active multi-selection
                            // carries the whole selection along; otherwise
                            // it's the normal single-item reorder/merge drag.
                            if case .app(let app) = item,
                               selectedBundleIdentifiers.count > 1,
                               selectedBundleIdentifiers.contains(app.bundleIdentifier) {
                                return NSItemProvider(object: "BULK:\(app.bundleIdentifier)" as NSString)
                            }
                            return NSItemProvider(object: String(index) as NSString)
                        }
                        .onDrop(of: [.text], delegate: ItemDropDelegate(
                            targetIndex: index,
                            items: $items,
                            onMergeIntoFolder: onMergeIntoFolder,
                            onBulkMergeIntoTarget: onBulkMergeIntoTarget
                        ))
                }
            }
            .padding(40)
            // `.overlay` (not a sibling `HStack` with a `Spacer`) so these
            // edge zones never influence the grid's own reported size — a
            // `Spacer` inside a plain ZStack sibling made the *whole page*
            // (and everything centered around it) greedily expand to fill
            // the screen, blowing up the layout well beyond the grid itself.
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: 24)
                    .contentShape(Rectangle())
                    .onDrop(of: [.text], delegate: EdgePageFlipDelegate(onFlip: { onRequestPageChange(-1) }))
            }
            .overlay(alignment: .trailing) {
                Color.clear
                    .frame(width: 24)
                    .contentShape(Rectangle())
                    .onDrop(of: [.text], delegate: EdgePageFlipDelegate(onFlip: { onRequestPageChange(1) }))
            }

            // A custom overlay (not `.sheet`) so opening/closing it can use
            // a fast scale+fade instead of the system sheet's slide — the
            // `.animation(value:)` below picks up every change to
            // `openFolder`, whatever triggered it (click, Return/Esc from
            // `OverlayWindowController`, or auto-close when it empties out).
            if let folder = openFolder {
                FolderView(
                    folder: folder,
                    metrics: metrics,
                    onSelect: onSelect,
                    onRemove: onRemoveApp,
                    onUninstall: onUninstallApp,
                    onRename: { newName in onRenameFolder(folder, newName) },
                    onEditingNameChanged: onEditingFolderNameChanged,
                    selectedBundleIdentifiers: selectedBundleIdentifiers,
                    onToggleSelectApp: onToggleSelectApp,
                    onBulkRemove: onBulkRemove,
                    onBulkUninstall: onBulkUninstall,
                    onDismiss: { openFolder = nil }
                )
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.16), value: openFolder)
    }

    @ViewBuilder
    private func itemView(for item: LaunchpadItem, at index: Int) -> some View {
        switch item {
        case .app(let app):
            AppIconView(
                app: app,
                metrics: metrics,
                isSelected: index == selectedIndex,
                onTap: { onSelect(app) },
                onRemove: { onRemoveApp(app) },
                onUninstall: { onUninstallApp(app) },
                isMultiSelected: selectedBundleIdentifiers.contains(app.bundleIdentifier),
                selectionCount: selectedBundleIdentifiers.count,
                onToggleSelect: { onToggleSelectApp(app) },
                onBulkRemove: onBulkRemove,
                onBulkUninstall: onBulkUninstall
            )
        case .folder(let folder):
            FolderIconView(
                folder: folder,
                metrics: metrics,
                isSelected: index == selectedIndex,
                onTap: { openFolder = folder }
            )
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
    let onBulkMergeIntoTarget: (LaunchpadItem) -> Void

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
            guard let string = reading as? String else { return }

            if string.hasPrefix("BULK:") {
                DispatchQueue.main.async {
                    guard items.indices.contains(targetIndex) else { return }
                    onBulkMergeIntoTarget(items[targetIndex])
                }
                return
            }

            guard let sourceIndex = Int(string) else { return }
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

// A thin strip at each edge of the grid: holding a drag over one for
// `holdThreshold` flips the page, so an icon can be dragged onto a page
// other than the one currently showing. Never actually accepts the drop
// itself (`performDrop` returns false) — it only watches for the hover.
private struct EdgePageFlipDelegate: DropDelegate {
    let onFlip: () -> Void

    private static let holdThreshold: TimeInterval = 0.6
    // Shared across both edges (left/right), like `hoverStartedAt` above —
    // fine since only one edge can be hovered at a time, and a fresh
    // `dropEntered` always replaces whatever was pending.
    private static var pendingFlip: DispatchWorkItem?

    func dropEntered(info: DropInfo) {
        let workItem = DispatchWorkItem(block: onFlip)
        Self.pendingFlip = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdThreshold, execute: workItem)
    }

    func dropExited(info: DropInfo) {
        Self.pendingFlip?.cancel()
        Self.pendingFlip = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        Self.pendingFlip?.cancel()
        Self.pendingFlip = nil
        return false
    }
}
