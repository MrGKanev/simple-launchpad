import SwiftUI

struct LaunchpadView: View {
    @ObservedObject var store: LaunchpadStore
    let onSelect: (AppInfo) -> Void
    let onDismiss: () -> Void

    private var searchResults: [AppInfo] {
        let allApps = store.pages.flatMap { $0 }.compactMap { item -> AppInfo? in
            if case .app(let app) = item { return app }
            return nil
        }
        return AppSearch.filter(allApps, query: store.searchQuery)
    }

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
                    SearchField(query: $store.searchQuery)
                        .frame(width: 280, height: 32)

                    if !store.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                        ScrollView {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.fixed(metrics.cellWidth), spacing: metrics.spacing), count: metrics.columns),
                                spacing: metrics.spacing
                            ) {
                                ForEach(searchResults, id: \.bundleIdentifier) { app in
                                    AppIconView(app: app, metrics: metrics, onTap: { onSelect(app) })
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
                                onSelect: onSelect,
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
                .padding(.top, 60)
                // Anchored to the top (not centered) so the search field stays put and
                // only the content below it grows/shrinks as results change — centering
                // here made the whole block visibly jump while typing a search query.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear { store.load() }
    }
}
