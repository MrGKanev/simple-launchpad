import Foundation

struct AppInfo: Equatable, Codable {
    let bundleIdentifier: String
    let name: String
    let path: URL
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
                results.append(AppInfo(bundleIdentifier: bundleIdentifier, name: name, path: url))
            }
        }
        return results
    }
}
