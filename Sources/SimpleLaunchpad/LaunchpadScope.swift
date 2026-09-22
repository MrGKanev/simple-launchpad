import Foundation

// What the category bar's pills select between — "All", the "Recently
// Added" pseudo-category, or one real `AppCategory`. A single-select scope
// (not a `Set`) matches how the newer macOS Launchpad/App grid's own
// category browser works: one view at a time, not a multi-filter.
enum LaunchpadScope: Equatable {
    case all
    case recentlyAdded
    case category(AppCategory)
}

// Governs how `LaunchpadStore.filteredResults` orders whatever `scope`
// (above) has already narrowed down to. Only meaningful for `.all` and
// `.category` — `.recentlyAdded` always orders by date added regardless, the
// same way stock Launchpad's own "Recently Added" isn't independently
// sortable either.
enum LaunchpadSortOption: String, CaseIterable, Identifiable, Hashable {
    case name
    case mostUsed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: return "Name"
        case .mostUsed: return "Most Used"
        }
    }
}

// See `LaunchpadStore.categoryBarScrollNudge`. `id` is a fresh `UUID` on
// every nudge (rather than deriving `Equatable`/`Hashable` from just
// `direction`) purely so SwiftUI's `.onChange` fires again for a second
// nudge in the same direction — two consecutive "step right"s are two
// distinct events, not one value staying the same.
struct CategoryBarScrollNudge: Equatable {
    enum Direction: Equatable {
        case backward
        case forward
    }

    let direction: Direction
    let id = UUID()
}
