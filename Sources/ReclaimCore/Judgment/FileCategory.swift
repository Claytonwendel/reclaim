import Foundation

/// Coarse file classification for cluster detection and human-readable
/// grouping. Extension-based — fast and good enough to say "you have a pile
/// of videos here."
enum FileCategory: String, Sendable {
    case video, image, audio, archive, installer, design, data, document, other

    var plural: String {
        switch self {
        case .video: "Videos"
        case .image: "Images"
        case .audio: "Audio files"
        case .archive: "Archives"
        case .installer: "Installers"
        case .design: "Design files"
        case .data: "Data/log files"
        case .document: "Documents"
        case .other: "Files"
        }
    }

    /// A short, honest hint about why this pile is often reclaimable.
    var hint: String {
        switch self {
        case .video: "Videos are the heaviest files on most Macs and are often one-off downloads or exports."
        case .image: "Image dumps and exports accumulate fast and are easy to forget."
        case .audio: "Audio exports and downloads add up."
        case .archive: "Archives are usually kept only until extracted."
        case .installer: "Installers are typically one-time use once the app is installed."
        case .design: "Design exports and old mockups pile up."
        case .data: "Data dumps, HAR captures, and logs are debug artifacts you rarely need again."
        case .document: "Old documents and exports."
        case .other: ""
        }
    }

    /// Piles of installers/archives/data are safely reclaimable (Blue);
    /// personal media stays Orange (review required).
    var riskTier: RiskTier {
        switch self {
        case .installer, .archive, .data: .blue
        default: .orange
        }
    }

    static func of(_ path: String) -> FileCategory {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "avi", "mkv", "webm", "m4v", "flv", "wmv": return .video
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "raw": return .image
        case "mp3", "wav", "aac", "flac", "m4a", "aiff": return .audio
        case "zip", "tar", "gz", "bz2", "7z", "rar", "iso", "xz": return .archive
        case "dmg", "pkg": return .installer
        case "fig", "sketch", "psd", "ai", "xd", "afdesign", "afphoto": return .design
        case "har", "log", "csv", "json", "ndjson", "sql", "dump": return .data
        case "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "pages", "key", "numbers": return .document
        default: return .other
        }
    }
}
