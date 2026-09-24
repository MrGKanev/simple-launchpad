import Foundation
import AppKit

// A hand-rolled updater instead of a framework like Sparkle: this app isn't
// code-signed/notarized, and Sparkle
// expects EdDSA-signed updates plus an appcast feed — infrastructure this
// project doesn't have. This instead reads GitHub's own "latest release"
// API directly and swaps the app bundle in place.
enum UpdateChecker {
    private static let latestReleaseAPIURL =
        URL(string: "https://api.github.com/repos/MrGKanev/simple-launchpad/releases/latest")!

    struct ReleaseInfo {
        let version: String
        let zipAssetURL: URL
    }

    enum UpdateError: LocalizedError {
        case noZipAsset
        case noAppInZip

        var errorDescription: String? {
            switch self {
            case .noZipAsset: return "The latest release has no downloadable build attached."
            case .noAppInZip: return "The downloaded update didn't contain an app."
            }
        }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    // Good enough for plain dotted version tags like "1.2" vs "1.10" —
    // compares numerically component by component rather than as strings.
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(remoteParts.count, localParts.count) {
            let remoteValue = index < remoteParts.count ? remoteParts[index] : 0
            let localValue = index < localParts.count ? localParts[index] : 0
            if remoteValue != localValue { return remoteValue > localValue }
        }
        return false
    }

    static func fetchLatestRelease() async throws -> ReleaseInfo? {
        var request = URLRequest(url: latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tagName = json["tag_name"] as? String,
            let assets = json["assets"] as? [[String: Any]]
        else { return nil }

        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        guard
            let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
            let downloadURLString = zipAsset["browser_download_url"] as? String,
            let downloadURL = URL(string: downloadURLString)
        else {
            throw UpdateError.noZipAsset
        }

        return ReleaseInfo(version: version, zipAssetURL: downloadURL)
    }

    // Downloads the release zip, unzips it, strips the quarantine flag macOS
    // stamps on anything fetched over the network (otherwise relaunching it
    // would hit Gatekeeper's "can't verify developer" prompt — this app
    // isn't notarized), swaps it in over the currently installed copy in
    // place, then relaunches the new one and quits this process.
    @MainActor
    static func downloadAndInstall(_ release: ReleaseInfo) async throws {
        let (tempZipURL, _) = try await URLSession.shared.download(from: release.zipAssetURL)

        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        try run("/usr/bin/ditto", ["-x", "-k", tempZipURL.path, workDir.path])

        guard let extractedApp = try FileManager.default
            .contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else {
            throw UpdateError.noAppInZip
        }

        try run("/usr/bin/xattr", ["-cr", extractedApp.path])

        let installedAppURL = Bundle.main.bundleURL
        // Replaces the installed app's contents in place while keeping its
        // location/name — the standard atomic-swap API, same trick Sparkle
        // itself uses to update a running app out from under itself.
        _ = try FileManager.default.replaceItemAt(installedAppURL, withItemAt: extractedApp)

        NSWorkspace.shared.open(installedAppURL)
        NSApp.terminate(nil)
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "UpdateChecker",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "\(launchPath) failed" : output]
            )
        }
        return output
    }
}
