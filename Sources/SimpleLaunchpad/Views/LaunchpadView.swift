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

    private var searchResults: [AppInfo] {
        let allApps = store.pages.flatMap { $0 }.compactMap { item -> AppInfo? in
            if case .app(let app) = item { return app }
            return nil
        }
        return AppSearch.filter(allApps, query: searchQuery)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.001) // catches taps on the empty background to dismiss
                .onTapGesture { onDismiss() }

            VStack(spacing: 24) {
                SearchField(query: searchQueryState.projectedValue)

                if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(90), spacing: 24), count: 7), spacing: 24) {
                            ForEach(searchResults, id: \.bundleIdentifier) { app in
                                AppIconView(app: app)
                                    .onTapGesture { onSelect(app) }
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
                        .gesture(
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
        }
        .onAppear { store.load() }
    }
}
