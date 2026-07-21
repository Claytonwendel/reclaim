import Foundation

/// How a recipe's cleanup is (eventually) executed. In the read-only phases
/// this is descriptive metadata only — nothing in the scanner mutates disk.
public enum ActionMethod: String, Codable, Sendable {
    /// Move to Reclaim quarantine / Trash (reversible file-based action).
    case quarantine
    /// Use the tool's own supported CLI (npm cache clean, brew cleanup, simctl…).
    case supportedCLI
    /// Surface for manual, per-item user review only. Never automated.
    case reviewOnly
    /// Do not touch under any circumstances. Report and explain only.
    case none
}

/// How well-established a recipe's knowledge is. Detection is always safe
/// (read-only), but only `.verified` recipes may ever gain automated actions.
public enum RecipeConfidence: String, Codable, Sendable {
    /// Path + removal method confirmed against primary vendor docs or a
    /// live verified cleanup (the case study).
    case verified
    /// Well-known community path; measure and report, but verify empirically
    /// before ever enabling an action.
    case communityKnown
}

/// A versioned, deterministic detection + (future) action rule.
/// This is the recipe schema from section 09 of the master plan.
/// AI may explain findings; only recipes may ever act.
public struct Recipe: Codable, Identifiable, Sendable {
    public let id: String                 // e.g. "dev.npm.cacache"
    public let displayName: String        // e.g. "npm downloaded package cache"
    public let group: String              // "AI tools", "Xcode", "JavaScript", …
    /// Paths to probe, `~` and glob (`*`) allowed. A recipe fires when any
    /// resolved path exists and exceeds `thresholdBytes`.
    public let paths: [String]
    public let riskTier: RiskTier
    /// Minimum allocated size before the finding is worth surfacing.
    public let thresholdBytes: Int64
    /// Process names that must NOT be running before action (e.g. ["Cursor"]).
    public let requiresQuit: [String]
    public let action: ActionMethod
    /// Plain-language: what this data is and why it exists.
    public let explanation: String
    /// Plain-language: what deletion changes / what re-downloads.
    public let impact: String
    /// Will it grow back? ("Likely to grow with package installs")
    public let recurrence: String
    /// Defaults to `.verified` for the original case-study catalog; new
    /// recipes sourced from community knowledge must pass `.communityKnown`.
    public let confidence: RecipeConfidence

    public init(
        id: String, displayName: String, group: String, paths: [String],
        riskTier: RiskTier, thresholdBytes: Int64 = 50 * 1024 * 1024,
        requiresQuit: [String] = [], action: ActionMethod,
        explanation: String, impact: String, recurrence: String,
        confidence: RecipeConfidence = .verified
    ) {
        self.id = id
        self.displayName = displayName
        self.group = group
        self.paths = paths
        self.riskTier = riskTier
        self.thresholdBytes = thresholdBytes
        self.requiresQuit = requiresQuit
        self.action = action
        self.explanation = explanation
        self.impact = impact
        self.recurrence = recurrence
        self.confidence = confidence
    }
}
