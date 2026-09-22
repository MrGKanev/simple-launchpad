import Foundation

// Mirrors the App Store's `LSApplicationCategoryType` buckets (the same
// `public.app-category.*` values Launchpad's own category browser groups
// apps by), collapsed to one flat list — the many `*-games` subcategories
// (action, puzzle, word, ...) all fold into `.games`, matching how Launchpad
// itself presents a single "Games" bucket rather than twenty tiny ones.
enum AppCategory: String, Codable, CaseIterable, Equatable, Hashable {
    case business
    case developerTools
    case education
    case entertainment
    case finance
    case games
    case graphicsAndDesign
    case healthAndFitness
    case lifestyle
    case medical
    case music
    case news
    case photography
    case productivity
    case reference
    case socialNetworking
    case sports
    case travel
    case utilities
    case video
    case weather
    case other

    var displayName: String {
        switch self {
        case .business: return "Business"
        case .developerTools: return "Developer Tools"
        case .education: return "Education"
        case .entertainment: return "Entertainment"
        case .finance: return "Finance"
        case .games: return "Games"
        case .graphicsAndDesign: return "Graphics & Design"
        case .healthAndFitness: return "Health & Fitness"
        case .lifestyle: return "Lifestyle"
        case .medical: return "Medical"
        case .music: return "Music"
        case .news: return "News"
        case .photography: return "Photo & Video"
        case .productivity: return "Productivity"
        case .reference: return "Reference"
        case .socialNetworking: return "Social Networking"
        case .sports: return "Sports"
        case .travel: return "Travel"
        case .utilities: return "Utilities"
        case .video: return "Video"
        case .weather: return "Weather"
        case .other: return "Other"
        }
    }

    // `raw` is the value straight out of Info.plist, e.g.
    // "public.app-category.developer-tools". Apps that don't declare one at
    // all (most in-house/Electron-style builds) — or declare something this
    // switch doesn't recognize — land in `.other` rather than disappearing
    // from every category filter.
    init(lsApplicationCategoryType raw: String?) {
        guard let suffix = raw?.split(separator: ".").last else {
            self = .other
            return
        }
        switch suffix {
        case "business": self = .business
        case "developer-tools": self = .developerTools
        case "education": self = .education
        case "entertainment": self = .entertainment
        case "finance": self = .finance
        case "graphics-design": self = .graphicsAndDesign
        case "healthcare-fitness": self = .healthAndFitness
        case "lifestyle": self = .lifestyle
        case "medical": self = .medical
        case "music": self = .music
        case "news": self = .news
        case "photography": self = .photography
        case "productivity": self = .productivity
        case "reference": self = .reference
        case "social-networking": self = .socialNetworking
        case "sports": self = .sports
        case "travel": self = .travel
        case "utilities": self = .utilities
        case "video": self = .video
        case "weather": self = .weather
        default:
            self = suffix.hasSuffix("-games") || suffix == "games" ? .games : .other
        }
    }
}
