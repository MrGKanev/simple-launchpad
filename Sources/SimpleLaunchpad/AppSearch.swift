import Foundation

enum AppSearch {
    static func filter(_ apps: [AppInfo], query: String) -> [AppInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return apps
            .filter { $0.name.range(of: trimmed, options: .caseInsensitive) != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
