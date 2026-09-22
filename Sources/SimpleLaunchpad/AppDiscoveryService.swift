import Foundation

struct AppInfo: Equatable, Codable {
    let bundleIdentifier: String
    let name: String
    let path: URL
    // Defaulted (rather than required) so existing call sites — tests in
    // particular, which don't care about categorization — keep compiling
    // unchanged; real entries get theirs filled in by `scan` below.
    var category: AppCategory = .other
    // Finder's own "Date Added" value for the .app bundle — drives the
    // "Recently Added" filter pill. Defaulted to nil for the same reason
    // as `category` above.
    var dateAdded: Date? = nil
}

enum AppDiscoveryService {
    static let defaultSearchPaths: [String] = [
        "/Applications",
        NSHomeDirectory() + "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities"
    ]

    static func scan(searchPaths: [String] = defaultSearchPaths, fileManager: FileManager = .default) -> [AppInfo] {
        var results: [AppInfo] = []
        for searchPath in searchPaths {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: searchPath) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let appPath = searchPath + "/" + entry
                let url = URL(fileURLWithPath: appPath)
                guard let bundle = Bundle(url: url) else { continue }
                let fallbackName = url.deletingPathExtension().lastPathComponent
                let bundleIdentifier = bundle.bundleIdentifier ?? fallbackName
                let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? fallbackName
                let categoryType = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
                let category = AppCategory(lsApplicationCategoryType: categoryType)
                let dateAdded = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate
                results.append(AppInfo(bundleIdentifier: bundleIdentifier, name: name, path: url, category: category, dateAdded: dateAdded))
            }
        }
        return results
    }
}
