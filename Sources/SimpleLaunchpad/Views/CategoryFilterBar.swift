import SwiftUI
import AppKit

// The row of category pills under the search field — mirrors the category
// browser in macOS's newer Launchpad/App grid. "All" and "Recently Added"
// come first, then one pill per category that actually has an installed
// app; tapping one narrows `LaunchpadStore.filteredResults` the same way
// typing a search query does. Dragging an icon from the filtered grid onto
// a category pill reassigns it there (`LaunchpadStore.setCategoryOverride`).
struct CategoryFilterBar: View {
    let categories: [AppCategory]
    @Binding var scope: LaunchpadScope
    @Binding var sortOption: LaunchpadSortOption
    // Whether the grid below is actually the flat, sortable one right now
    // (search active, or a category/"Recently Added" pill selected) — the
    // normal paged grid ignores `sortOption` entirely (it's manually
    // ordered), so the sort control only makes sense to show alongside the
    // flat one.
    let isFiltering: Bool
    let metrics: IconGridMetrics
    let palette: LaunchpadPalette
    // Mirrored into `LaunchpadStore.isHoveringCategoryBar` — see that
    // property for why `OverlayWindowController` needs to know this.
    @Binding var isHovering: Bool
    // Set by `OverlayWindowController` when a plain mouse wheel scrolls
    // while hovering this bar — see `LaunchpadStore.categoryBarScrollNudge`.
    let scrollNudge: CategoryBarScrollNudge?
    // nil bundle identifier means nothing is currently being dragged — see
    // `LaunchpadView`'s `.onDrag` on each filtered-grid icon.
    let onDropBundleIdentifier: (String, AppCategory) -> Void

    // Stable ids for `ScrollViewReader.scrollTo`, in display order — used by
    // the chevron buttons below to step through the row a few pills at a
    // time when there are more than fit on screen at once.
    private enum PillID: Hashable {
        case all
        case recentlyAdded
        case category(AppCategory)
    }
    private var pillIDs: [PillID] { [.all, .recentlyAdded] + categories.map(PillID.category) }

    // ponytail: manual `SwiftUI.State<Value>` wiring instead of the `@State`
    // attribute — see the comment in LaunchpadView.swift for why (this SDK's
    // `@State` macro plugin isn't available under Xcode Command Line Tools).
    private var focusedIndexState = SwiftUI.State(wrappedValue: 0)
    private var focusedIndex: Int {
        get { focusedIndexState.wrappedValue }
        nonmutating set { focusedIndexState.wrappedValue = newValue }
    }

    private let chevronStep = 3
    private var scrollViewState = SwiftUI.State<NSScrollView?>(initialValue: nil)
    private var dragOriginState = SwiftUI.State<CGFloat?>(initialValue: nil)

    init(
        categories: [AppCategory],
        scope: Binding<LaunchpadScope>,
        sortOption: Binding<LaunchpadSortOption>,
        isFiltering: Bool,
        metrics: IconGridMetrics,
        palette: LaunchpadPalette,
        isHovering: Binding<Bool>,
        scrollNudge: CategoryBarScrollNudge?,
        onDropBundleIdentifier: @escaping (String, AppCategory) -> Void
    ) {
        self.categories = categories
        self._scope = scope
        self._sortOption = sortOption
        self.isFiltering = isFiltering
        self.metrics = metrics
        self.palette = palette
        self._isHovering = isHovering
        self.scrollNudge = scrollNudge
        self.onDropBundleIdentifier = onDropBundleIdentifier
    }

    var body: some View {
        VStack(spacing: 8 * metrics.scale) {
            ScrollViewReader { proxy in
                // Chevrons sit beside the scrollable row (not layered on top
                // of it) so they never cover the first/last pill — only
                // reserved once there are actually enough pills to overflow
                // it, a rough count-based stand-in for measuring real
                // overflow (pill width varies with each label). A trackpad
                // swipe (now unblocked by `isHovering`, see `LaunchpadStore`)
                // keeps working the same as it always would; the chevrons
                // are the reliable fallback for a mouse with no horizontal
                // scroll axis.
                HStack(spacing: 4 * metrics.scale) {
                    if pillIDs.count > 6 {
                        chevron(systemName: "chevron.left") { step(.backward, proxy: proxy) }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10 * metrics.scale) {
                            pill(title: "All", isSelected: scope == .all) { scope = .all }
                                .id(PillID.all)
                            pill(title: "Recently Added", isSelected: scope == .recentlyAdded) {
                                scope = scope == .recentlyAdded ? .all : .recentlyAdded
                            }
                            .id(PillID.recentlyAdded)
                            ForEach(categories, id: \.self) { category in
                                pill(title: category.displayName, isSelected: scope == .category(category), isDropTarget: true) {
                                    scope = scope == .category(category) ? .all : .category(category)
                                } onDrop: { bundleIdentifier in
                                    onDropBundleIdentifier(bundleIdentifier, category)
                                }
                                .id(PillID.category(category))
                            }
                        }
                        .padding(.horizontal, 2 * metrics.scale)
                        .background(CategoryScrollReader { scrollView in
                            if scrollViewState.wrappedValue !== scrollView {
                                scrollViewState.wrappedValue = scrollView
                            }
                        })
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { value in
                                    guard let scrollView = scrollViewState.wrappedValue,
                                          let document = scrollView.documentView else { return }
                                    let clip = scrollView.contentView
                                    if dragOriginState.wrappedValue == nil {
                                        dragOriginState.wrappedValue = clip.bounds.origin.x
                                    }
                                    let origin = dragOriginState.wrappedValue ?? 0
                                    let limit = max(0, document.frame.width - clip.bounds.width)
                                    clip.scroll(to: NSPoint(x: min(limit, max(0, origin - value.translation.width)), y: clip.bounds.origin.y))
                                    scrollView.reflectScrolledClipView(clip)
                                }
                                .onEnded { _ in dragOriginState.wrappedValue = nil }
                        )
                    }
                    .frame(maxWidth: .infinity)

                    if pillIDs.count > 6 {
                        chevron(systemName: "chevron.right") { step(.forward, proxy: proxy) }
                    }
                }
                .onHover { isHovering = $0 }
                .onDisappear { isHovering = false }
                // A plain (non-trackpad) mouse wheel has no horizontal axis
                // for the `ScrollView` above to react to on its own — see
                // `OverlayWindowController.handleScroll`, which turns that
                // into a nudge here instead.
                .onChange(of: scrollNudge) { nudge in
                    guard let nudge else { return }
                    step(nudge.direction, proxy: proxy)
                }
            }
            .frame(maxWidth: metrics.cellWidth * 7 + metrics.spacing * 6)

            // Hidden outside the flat/filtered grid (nothing to sort yet),
            // and for "Recently Added" — it has its own fixed date order,
            // same as stock Launchpad's equivalent view isn't independently
            // re-sortable either (see `LaunchpadStore.filteredResults`).
            if isFiltering, scope != .recentlyAdded {
                Picker("Sort", selection: $sortOption) {
                    ForEach(LaunchpadSortOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180 * metrics.scale)
                .labelsHidden()
            }
        }
    }

    // Shared by the chevron buttons and `scrollNudge` (a plain mouse
    // wheel's vertical delta, translated upstream in
    // `OverlayWindowController`) — moves `focusedIndex` a few pills in the
    // given direction and animates the row to it.
    private func step(_ direction: CategoryBarScrollNudge.Direction, proxy: ScrollViewProxy) {
        switch direction {
        case .backward:
            focusedIndex = max(0, focusedIndex - chevronStep)
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(pillIDs[focusedIndex], anchor: .leading)
            }
        case .forward:
            focusedIndex = min(pillIDs.count - 1, focusedIndex + chevronStep)
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(pillIDs[focusedIndex], anchor: .trailing)
            }
        }
    }

    private func pill(
        title: String,
        isSelected: Bool,
        isDropTarget: Bool = false,
        action: @escaping () -> Void,
        onDrop: ((String) -> Void)? = nil
    ) -> some View {
        PillButton(
            title: title,
            isSelected: isSelected,
            metrics: metrics,
            palette: palette,
            action: action,
            onDropBundleIdentifier: isDropTarget ? onDrop : nil
        )
    }

    private func chevron(systemName: String, action: @escaping () -> Void) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11 * metrics.scale, weight: .bold))
            // `pillSelectedText`/`pillSelectedFill` are the same contrasting
            // pair a selected pill uses (e.g. black-on-white in dark mode) —
            // `pillText` alone is nearly the same shade as `pillSelectedFill`
            // and made the glyph all but invisible against this circle.
            .foregroundStyle(palette.pillSelectedText)
            .frame(width: 22 * metrics.scale, height: 22 * metrics.scale)
            .background(Circle().fill(palette.pillSelectedFill))
            .contentShape(Circle())
            .onTapGesture(perform: action)
    }
}

// Reuse the native scroll view so mouse dragging and trackpad scrolling
// share the same content offset and bounds.
private struct CategoryScrollReader: NSViewRepresentable {
    let onResolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            if let scrollView = view?.enclosingScrollView { onResolve(scrollView) }
        }
    }
}

private struct PillButton: View {
    let title: String
    let isSelected: Bool
    let metrics: IconGridMetrics
    let palette: LaunchpadPalette
    let action: () -> Void
    let onDropBundleIdentifier: ((String) -> Void)?

    init(
        title: String,
        isSelected: Bool,
        metrics: IconGridMetrics,
        palette: LaunchpadPalette,
        action: @escaping () -> Void,
        onDropBundleIdentifier: ((String) -> Void)?
    ) {
        self.title = title
        self.isSelected = isSelected
        self.metrics = metrics
        self.palette = palette
        self.action = action
        self.onDropBundleIdentifier = onDropBundleIdentifier
    }

    // ponytail: manual `SwiftUI.State<Value>` wiring instead of the `@State`
    // attribute — see the comment in LaunchpadView.swift for why (this SDK's
    // `@State` macro plugin isn't available under Xcode Command Line Tools).
    private var isDropTargetedState = SwiftUI.State(wrappedValue: false)
    private var isDropTargeted: Bool {
        get { isDropTargetedState.wrappedValue }
        nonmutating set { isDropTargetedState.wrappedValue = newValue }
    }

    var body: some View {
        Text(title)
            .font(.system(size: 13 * metrics.scale, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? palette.pillSelectedText : palette.pillText)
            .padding(.horizontal, 14 * metrics.scale)
            .padding(.vertical, 6 * metrics.scale)
            .background(
                Capsule().fill(
                    isDropTargeted ? palette.pillDropTargetFill : (isSelected ? palette.pillSelectedFill : palette.pillFill)
                )
            )
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .modifier(DropModifier(isTargeted: Binding(
                get: { isDropTargeted },
                set: { isDropTargeted = $0 }
            ), onDrop: onDropBundleIdentifier))
    }
}

// Isolated behind a `ViewModifier` so a pill with no drop handler (e.g.
// "All"/"Recently Added") doesn't pay for a `.onDrop` at all rather than
// registering one that always rejects.
private struct DropModifier: ViewModifier {
    @Binding var isTargeted: Bool
    let onDrop: ((String) -> Void)?

    func body(content: Content) -> some View {
        if let onDrop {
            content.onDrop(of: [.text], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                provider.loadObject(ofClass: NSString.self) { reading, _ in
                    guard let string = reading as? String, string.hasPrefix("APP:") else { return }
                    let bundleIdentifier = String(string.dropFirst("APP:".count))
                    DispatchQueue.main.async { onDrop(bundleIdentifier) }
                }
                return true
            }
        } else {
            content
        }
    }
}
