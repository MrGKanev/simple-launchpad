import SwiftUI
import AppKit

struct LaunchpadView: View {
    @ObservedObject var store: LaunchpadStore
    @ObservedObject var preferences: AppPreferences
    let onSelect: (AppInfo) -> Void
    let onDismiss: () -> Void

    // Resolved once per render from the "Appearance" Settings preference —
    // `.system` mirrors whatever macOS is currently in (so the overlay
    // still looks the same as it always did unless the user opts into an
    // explicit Light/Dark override). Threaded explicitly through every
    // child view's `palette:` parameter (the same convention `metrics:`
    // already uses) rather than SwiftUI's environment, since this view
    // would otherwise need to apply `.preferredColorScheme` to its own
    // returned content and then separately read it back for its own inline
    // colors — two different things trying to agree on one value.
    private var palette: LaunchpadPalette {
        switch preferences.appearance {
        case .system:
            return LaunchpadPalette(isDark: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) != .aqua)
        case .light:
            return LaunchpadPalette(isDark: false)
        case .dark:
            return LaunchpadPalette(isDark: true)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = IconGridMetrics.fitting(geometry.size)
            let palette = palette

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

                palette.backdropTint // tint over the blur so icons/text stay readable in either theme
                    .allowsHitTesting(false)
                    .ignoresSafeArea()

                VStack(spacing: 28 * metrics.scale) {
                    // Same 2.8-wide ratio the field always had, scaled off
                    // the grid's own screen-relative metrics instead of a
                    // fixed pixel size. Height is a bit taller than that
                    // original 0.32 ratio for a roomier field — font size is
                    // set independently below so it doesn't grow with it.
                    // The `Capsule` fill (rather than the search field's own
                    // native bezel — see `SearchField`) is the same shape
                    // and shade as an unselected category pill, so the two
                    // rows read as one matching set of controls.
                    if preferences.showSearchField {
                        ZStack {
                            Capsule().fill(palette.pillFill)
                            SearchField(
                                query: $store.searchQuery,
                                fontSize: 20 * metrics.scale,
                                palette: palette,
                                onCreate: { store.searchField = $0 }
                            )
                                .padding(.horizontal, 16 * metrics.scale)
                        }
                        .frame(width: metrics.cellWidth * 2.8, height: metrics.cellHeight * 0.4)
                        .clipShape(Capsule())
                    }

                    if preferences.showCategoryBar, !store.availableCategories.isEmpty {
                        CategoryFilterBar(
                            categories: store.availableCategories,
                            scope: $store.scope,
                            sortOption: $store.sortOption,
                            isFiltering: store.isFiltering,
                            metrics: metrics,
                            palette: palette,
                            isHovering: $store.isHoveringCategoryBar,
                            scrollNudge: store.categoryBarScrollNudge,
                            onDropBundleIdentifier: { bundleIdentifier, category in
                                store.setCategoryOverride(category, forBundleIdentifier: bundleIdentifier)
                            }
                        )
                    }

                    if store.isFiltering {
                        ScrollView {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.fixed(metrics.cellWidth), spacing: metrics.spacing), count: metrics.columns),
                                spacing: metrics.spacing
                            ) {
                                ForEach(Array(store.filteredResults.enumerated()), id: \.element.bundleIdentifier) { index, app in
                                    AppIconView(
                                        app: app,
                                        metrics: metrics,
                                        isSelected: store.hasKeyboardSelection && index == store.selectedIndex,
                                        palette: palette,
                                        onTap: { onSelect(app) },
                                        onRemove: { store.removeApp(app) },
                                        onUninstall: { store.uninstallApp(app) },
                                        isMultiSelected: store.selectedBundleIdentifiers.contains(app.bundleIdentifier),
                                        selectionCount: store.selectedBundleIdentifiers.count,
                                        onToggleSelect: { store.toggleSelection(app) },
                                        onBulkRemove: { store.removeSelectedApps() },
                                        onBulkUninstall: { store.uninstallSelectedApps() }
                                    )
                                    // Lets a category pill above accept this icon
                                    // as a manual category reassignment — see
                                    // `CategoryFilterBar`. Only the filtered grid
                                    // (search/category view) supports this, not
                                    // the normal paged grid, since that's the
                                    // context where category pills are actually
                                    // visible alongside the icons.
                                    .onDrag { NSItemProvider(object: "APP:\(app.bundleIdentifier)" as NSString) }
                                }
                            }
                            .padding(40 * metrics.scale)
                        }
                        // A bare `ScrollView` has no intrinsic height of its own,
                        // so it expands to fill all available space in this
                        // VStack — taller than the fixed 5-row grid below ever
                        // is. Since the VStack is centered in the full-screen
                        // frame, that extra height pushed everything (including
                        // the search field) upward the instant a search started.
                        // Pinning it to the same height as the normal 5-row page
                        // keeps the layout stable when switching in and out of
                        // search.
                        .frame(height: 5 * metrics.cellHeight + 4 * metrics.spacing)
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
                                palette: palette,
                                selectedIndex: store.selectedIndex,
                                hasKeyboardSelection: store.hasKeyboardSelection,
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
                            HStack(spacing: 8 * metrics.scale) {
                                ForEach(store.pages.indices, id: \.self) { index in
                                    Circle()
                                        .fill(index == store.currentPage ? palette.dotActive : palette.dotInactive)
                                        .frame(width: 8 * metrics.scale, height: 8 * metrics.scale)
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
