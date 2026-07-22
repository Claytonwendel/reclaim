import Foundation

/// Why Reclaim thinks a personal file might be unwanted. Each reason is a
/// plain-language judgment the user can immediately understand and overrule.
public enum SuggestionReason: String, Codable, Sendable {
    case oldAndLarge          // big + untouched for a long time
    case veryLarge            // big regardless of age (review-worthy)
    case duplicate            // same content as another file
    case oldScreenRecording   // screen recordings pile up, rarely rewatched
    case oldScreenshot        // screenshot clutter
    case installerForInstalledApp  // DMG/PKG for an app already installed
    case oldDownload          // downloaded long ago, never touched since
    case oldDeviceBackup      // iOS backup, possibly a device you no longer own
    case oldAttachment        // received attachment past a keep window
}

/// A single personal-file suggestion. Always personal content → the tier is
/// Orange or Blue and the action is never automatic. The judgment is advisory:
/// Reclaim explains its reasoning and confidence; the user decides.
public struct Suggestion: Codable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let sizeBytes: Int64
    public let reason: SuggestionReason
    /// Plain-language "here's why we flagged this" — shown verbatim to the user.
    public let rationale: String
    public let lastModified: Date?
    public let lastAccessed: Date?
    /// 0–1. How confident Reclaim is that this is genuinely unwanted.
    /// Never used to auto-delete — only to sort and to set tone.
    public let confidence: Double
    public let riskTier: RiskTier
    /// For duplicates: the path this is a duplicate of (the copy we'd keep).
    public let duplicateOf: String?

    public init(path: String, sizeBytes: Int64, reason: SuggestionReason,
                rationale: String, lastModified: Date?, lastAccessed: Date?,
                confidence: Double, riskTier: RiskTier, duplicateOf: String? = nil) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.reason = reason
        self.rationale = rationale
        self.lastModified = lastModified
        self.lastAccessed = lastAccessed
        self.confidence = confidence
        self.riskTier = riskTier
        self.duplicateOf = duplicateOf
    }
}

/// One file inside a cluster — enough to browse, preview, and act on it.
public struct ClusterFile: Codable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let bytes: Int64
    public let modified: Date?

    public init(path: String, bytes: Int64, modified: Date?) {
        self.path = path
        self.bytes = bytes
        self.modified = modified
    }
}

/// An accumulation of many similar files — the "death by a thousand cuts"
/// pattern the case study identified ("the largest wins are scattered").
/// One 20 MB video is nothing; 127 of them is 2.5 GB.
public struct Cluster: Codable, Identifiable, Sendable {
    public var id: String { "\(directory):\(category)" }
    public let directory: String        // e.g. "Downloads"
    public let category: String         // "Videos", "Screenshots", …
    public let count: Int
    public let totalBytes: Int64
    public let oldest: Date?
    public let newest: Date?
    public let rationale: String
    public let riskTier: RiskTier
    /// Every file in the cluster, largest first — for the in-app browser.
    public let files: [ClusterFile]

    public init(directory: String, category: String, count: Int, totalBytes: Int64,
                oldest: Date?, newest: Date?, rationale: String,
                riskTier: RiskTier, files: [ClusterFile]) {
        self.directory = directory
        self.category = category
        self.count = count
        self.totalBytes = totalBytes
        self.oldest = oldest
        self.newest = newest
        self.rationale = rationale
        self.riskTier = riskTier
        self.files = files
    }
}

public struct JudgmentReport: Codable, Sendable {
    public let scannedAt: Date
    public let suggestions: [Suggestion]
    public let clusters: [Cluster]
    public let elapsedSeconds: Double

    public init(scannedAt: Date, suggestions: [Suggestion],
                clusters: [Cluster] = [], elapsedSeconds: Double) {
        self.scannedAt = scannedAt
        self.suggestions = suggestions
        self.clusters = clusters
        self.elapsedSeconds = elapsedSeconds
    }

    public var totalBytes: Int64 { suggestions.reduce(0) { $0 + $1.sizeBytes } }

    public func grouped() -> [(SuggestionReason, [Suggestion])] {
        Dictionary(grouping: suggestions, by: \.reason)
            .sorted { lhs, rhs in
                lhs.value.reduce(0) { $0 + $1.sizeBytes } > rhs.value.reduce(0) { $0 + $1.sizeBytes }
            }
    }
}
