import SwiftUI

struct LaunchpadView: View {
    @ObservedObject var store: LaunchpadStore
    let onSelect: (AppInfo) -> Void
    let onDismiss: () -> Void

    // ponytail: manual `SwiftUI.State<Value>` wiring instead of the `@State` attribute.
    // On this SDK, `@State` expands via a compiler macro (SwiftUIMacros.StateMacro)
    // whose plugin binary ships only inside Xcode.app; under Xcode Command Line
    // Tools alone the plugin can't be found and `swift build` fails outright.
    // `State<Value>` is still a plain struct underneath, so using it directly
    // (bypassing the attribute sugar) is behaviorally identical without needing
    // the missing macro plugin. Revert to `@State` once building with full Xcode.
    private var currentPageState = SwiftUI.State(wrappedValue: 0)
    private var currentPage: Int {
        get { currentPageState.wrappedValue }
        nonmutating set { currentPageState.wrappedValue = newValue }
    }

    private var searchQueryState = SwiftUI.State(wrappedValue: "")
    private var searchQuery: String {
        get { searchQueryState.wrappedValue }
        nonmutating set { searchQueryState.wrappedValue = newValue }
    }

    private var lastPageChangeState = SwiftUI.State(wrappedValue: Date.distantPast)
    private var lastPageChange: Date {
        get { lastPageChangeState.wrappedValue }
        nonmutating set { lastPageChangeState.wrappedValue = newValue }
    }

    private var searchResults: [AppInfo] {
        let allApps = store.pages.flatMap { $0 }.compactMap { item -> AppInfo? in
            if case .app(let app) = item { return app }
            return nil
        }
        return AppSearch.filter(allApps, query: searchQuery)
    }

    // Same left/right convention as the swipe DragGesture below: a negative
    // delta (scrolling/swiping toward the left) advances to the next page.
    // Debounced so one trackpad scroll gesture (which fires many small
    // events) only flips a single page instead of racing through several.
    private func handleScroll(_ delta: CGFloat) {
        guard searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard abs(delta) > 4 else { return }
        guard Date().timeIntervalSince(lastPageChange) > 0.5 else { return }
        if delta < 0, store.pages.indices.contains(currentPage + 1) {
            currentPage += 1
            lastPageChange = Date()
        } else if delta > 0, store.pages.indices.contains(currentPage - 1) {
            currentPage -= 1
            lastPageChange = Date()
        }
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
                    SearchField(query: searchQueryState.projectedValue)

                    if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
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
                        // page directly and drive `currentPage` ourselves via tappable dots
                        // and a DragGesture below.
                        if store.pages.indices.contains(currentPage) {
                            let pageIndex = currentPage
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
                                        if value.translation.width < 0, store.pages.indices.contains(currentPage + 1) {
                                            currentPage += 1
                                        } else if value.translation.width > 0, store.pages.indices.contains(currentPage - 1) {
                                            currentPage -= 1
                                        }
                                    }
                            )
                        }

                        if store.pages.count > 1 {
                            HStack(spacing: 8) {
                                ForEach(store.pages.indices, id: \.self) { index in
                                    Circle()
                                        .fill(index == currentPage ? Color.white : Color.white.opacity(0.4))
                                        .frame(width: 8, height: 8)
                                        .onTapGesture { currentPage = index }
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
                .background(ScrollPageMonitor(onScroll: handleScroll))
            }
        }
        .onAppear { store.load() }
    }
}
