import Foundation

struct LayoutFile: Codable, Equatable {
    var pages: [[LayoutItem]]
}

enum LayoutItem: Codable, Equatable {
    case app(bundleIdentifier: String)
    case folder(name: String, bundleIdentifiers: [String])

    private enum CodingKeys: String, CodingKey {
        case type, bundleIdentifier, name, bundleIdentifiers
    }

    private enum Kind: String, Codable {
        case app, folder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .app:
            let id = try container.decode(String.self, forKey: .bundleIdentifier)
            self = .app(bundleIdentifier: id)
        case .folder:
            let name = try container.decode(String.self, forKey: .name)
            let ids = try container.decode([String].self, forKey: .bundleIdentifiers)
            self = .folder(name: name, bundleIdentifiers: ids)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let bundleIdentifier):
            try container.encode(Kind.app, forKey: .type)
            try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        case .folder(let name, let bundleIdentifiers):
            try container.encode(Kind.folder, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(bundleIdentifiers, forKey: .bundleIdentifiers)
        }
    }
}

enum LayoutPersistence {
    static func defaultURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("SimpleLaunchpad", isDirectory: true)
            .appendingPathComponent("layout.json")
    }

    static func load(from url: URL) -> LayoutFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LayoutFile.self, from: data)
    }

    static func save(_ layout: LayoutFile, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(layout)
        try data.write(to: url, options: .atomic)
    }
}
