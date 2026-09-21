import SwiftUI

struct LaunchpadView: View {
    @ObservedObject var store: LaunchpadStore
    let onSelect: (AppInfo) -> Void
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let metrics = IconGridMetrics.fitting(geometry.size)

            ZStack {
                VisualEffectBlur(material: .fullScreenUI, blendingMode: .behindWindow)
                    .ignoresSafeArea()

                Color.black.opacity(0.001) // catches taps on the empty background to dismiss
                    .onTapGesture {
                        // A folder is no longer a modal sheet — a click
                        // outside its small box but still on this same
                        // background would otherwise fall all the way
                        // through to here and close the whole overlay
                        // instead of just the folder.
                        if store.openFolder != nil {
                            store.openFolder = nil
                        } else {
                            onDismiss()
                        }
                    }

                Color.black.opacity(0.18) // dark tint over the blur so icons/text stay readable
                    .allowsHitTesting(false)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Same 2.8:0.32 width:height ratio the field always had,
                    // now scaled off the grid's own screen-relative metrics
                    // instead of a fixed pixel size.
                    SearchField(query: $store.searchQuery)
                        .frame(width: metrics.cellWidth * 2.8, height: metrics.cellHeight * 0.32)

                    if !store.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                        ScrollView {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.fixed(metrics.cellWidth), spacing: metrics.spacing), count: metrics.columns),
                                spacing: metrics.spacing
                            ) {
                                ForEach(Array(store.searchResults.enumerated()), id: \.element.bundleIdentifier) { index, app in
                                    AppIconView(
                                        app: app,
                                        metrics: metrics,
                                        isSelected: index == store.selectedIndex,
                                        onTap: { onSelect(app) },
                                        onRemove: { store.removeApp(app) },
                                        onUninstall: { store.uninstallApp(app) },
                                        isMultiSelected: store.selectedBundleIdentifiers.contains(app.bundleIdentifier),
                                        selectionCount: store.selectedBundleIdentifiers.count,
                                        onToggleSelect: { store.toggleSelection(app) },
                                        onBulkRemove: { store.removeSelectedApps() },
                                        onBulkUninstall: { store.uninstallSelectedApps() }
                                    )
                                }
                            }
                            .padding(40)
                        }
                    } else {
                        // ponytail: `.tabViewStyle(.page)` (PageTabViewStyle) is marked
                        // `@available(macOS, unavailable)` in SwiftUI — it only exists on
                        // iOS/tvOS/watchOS/visionOS, and macOS's default TabView style has
                        // no swipe gesture. So instead of a TabView we render the current
                        // page directly and drive `store.currentPage` ourselves via
                        // tappable dots and a DragGesture below (scrolling and arrow keys
                        // are handled window-wide by `OverlayWindowController`).
                        if store.pages.indices.contains(store.currentPage) {
                            let pageIndex = store.currentPage
                            PageView(
                                items: Binding(
                                    get: { store.pages[pageIndex] },
                                    set: { newValue in
                                        store.pages[pageIndex] = newValue
                                        store.save()
                                    }
                                ),
                                metrics: metrics,
                                selectedIndex: store.selectedIndex,
                                openFolder: $store.openFolder,
                                onSelect: onSelect,
                                onRemoveApp: { app in store.removeApp(app) },
                                onUninstallApp: { app in store.uninstallApp(app) },
                                onRenameFolder: { folder, newName in store.renameFolder(folder, to: newName) },
                                onEditingFolderNameChanged: { editing in store.isEditingFolderName = editing },
                                onMergeIntoFolder: { source, target in
                                    let merged = LaunchpadStore.mergingIntoFolder(
                                        sourceIndex: source,
                                        targetIndex: target,
                                        items: store.pages[pageIndex]
                                    )
                                    store.pages[pageIndex] = merged
                                    store.save()
                                },
                                selectedBundleIdentifiers: store.selectedBundleIdentifiers,
                                onToggleSelectApp: { app in store.toggleSelection(app) },
                                onBulkRemove: { store.removeSelectedApps() },
                                onBulkUninstall: { store.uninstallSelectedApps() },
                                onBulkMergeIntoTarget: { target in store.mergeSelectedApps(intoTarget: target) },
                                onRequestPageChange: { offset in
                                    let target = store.currentPage + offset
                                    guard store.pages.indices.contains(target) else { return }
                                    store.currentPage = target
                                }
                            )
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 40)
                                    .onEnded { value in
                                        if value.translation.width < 0, store.pages.indices.contains(store.currentPage + 1) {
                                            store.currentPage += 1
                                        } else if value.translation.width > 0, store.pages.indices.contains(store.currentPage - 1) {
                                            store.currentPage -= 1
                                        }
                                    }
                            )
                        }

                        if store.pages.count > 1 {
                            HStack(spacing: 8) {
                                ForEach(store.pages.indices, id: \.self) { index in
                                    Circle()
                                        .fill(index == store.currentPage ? Color.white : Color.white.opacity(0.4))
                                        .frame(width: 8, height: 8)
                                        .onTapGesture { store.currentPage = index }
                                        // Dragging a dot onto another reorders the
                                        // pages themselves, the same drag-to-reorder
                                        // convention as icons within a page.
                                        .onDrag { NSItemProvider(object: "PAGE:\(index)" as NSString) }
                                        .onDrop(of: [.text], isTargeted: nil) { providers in
                                            guard let provider = providers.first else { return false }
                                            provider.loadObject(ofClass: NSString.self) { reading, _ in
                                                guard let string = reading as? String, string.hasPrefix("PAGE:"),
                                                      let sourceIndex = Int(string.dropFirst(5))
                                                else { return }
                                                DispatchQueue.main.async {
                                                    guard sourceIndex != index,
                                                          store.pages.indices.contains(sourceIndex),
                                                          store.pages.indices.contains(index)
                                                    else { return }
                                                    let destination = index > sourceIndex ? index + 1 : index
                                                    store.pages.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
                                                    store.currentPage = index
                                                    store.save()
                                                }
                                            }
                                            return true
                                        }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .onAppear { store.load() }
    }
}
