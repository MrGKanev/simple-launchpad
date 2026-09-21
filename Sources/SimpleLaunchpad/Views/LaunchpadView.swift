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
                    .onTapGesture { onDismiss() }

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
                                        onUninstall: { store.uninstallApp(app) }
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
                                onMergeIntoFolder: { source, target in
                                    let merged = LaunchpadStore.mergingIntoFolder(
                                        sourceIndex: source,
                                        targetIndex: target,
                                        items: store.pages[pageIndex]
                                    )
                                    store.pages[pageIndex] = merged
                                    store.save()
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
