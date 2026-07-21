import Foundation

/// A concrete, measured result of a recipe firing on this Mac.
public struct Finding: Codable, Identifiable, Sendable {
    public var id: String { "\(recipeID):\(path)" }
    public let recipeID: String
    public let displayName: String
    public let group: String
    public let path: String               // resolved absolute path
    public let allocatedBytes: Int64      // physical size on disk
    public let apparentBytes: Int64       // logical size (du-style)
    public let riskTier: RiskTier
    public let action: ActionMethod
    public let explanation: String
    public let impact: String
    public let recurrence: String
    public let lastModified: Date?
    /// True if a process listed in the recipe's requiresQuit is running now.
    public let blockingAppRunning: Bool
    /// Paths the scanner could not read ("Operation not permitted" = hard stop).
    public let skippedProtectedPaths: [String]

    public init(
        recipeID: String, displayName: String, group: String, path: String,
        allocatedBytes: Int64, apparentBytes: Int64, riskTier: RiskTier,
        action: ActionMethod, explanation: String, impact: String,
        recurrence: String, lastModified: Date?, blockingAppRunning: Bool,
        skippedProtectedPaths: [String]
    ) {
        self.recipeID = recipeID
        self.displayName = displayName
        self.group = group
        self.path = path
        self.allocatedBytes = allocatedBytes
        self.apparentBytes = apparentBytes
        self.riskTier = riskTier
        self.action = action
        self.explanation = explanation
        self.impact = impact
        self.recurrence = recurrence
        self.lastModified = lastModified
        self.blockingAppRunning = blockingAppRunning
        self.skippedProtectedPaths = skippedProtectedPaths
    }
}

/// The output of one read-only scan session.
public struct ScanReport: Codable, Sendable {
    public let scannedAt: Date
    public let hostname: String
    public let volumeTotalBytes: Int64
    public let volumeFreeBytes: Int64
    public let findings: [Finding]
    public let elapsedSeconds: Double

    public init(scannedAt: Date, hostname: String, volumeTotalBytes: Int64,
                volumeFreeBytes: Int64, findings: [Finding], elapsedSeconds: Double) {
        self.scannedAt = scannedAt
        self.hostname = hostname
        self.volumeTotalBytes = volumeTotalBytes
        self.volumeFreeBytes = volumeFreeBytes
        self.findings = findings
        self.elapsedSeconds = elapsedSeconds
    }

    /// Conservative headline: Green-tier findings not blocked by a running app.
    public var recoverableNowBytes: Int64 {
        findings.filter { $0.riskTier == .green && !$0.blockingAppRunning }
                .reduce(0) { $0 + $1.allocatedBytes }
    }

    /// Everything surfaced for explicit review (Yellow + Orange).
    public var reviewBytes: Int64 {
        findings.filter { $0.riskTier == .yellow || $0.riskTier == .orange }
                .reduce(0) { $0 + $1.allocatedBytes }
    }
}

public enum ByteFormatter {
    public static func string(_ bytes: Int64) -> String {
        let f = Foundation.ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
