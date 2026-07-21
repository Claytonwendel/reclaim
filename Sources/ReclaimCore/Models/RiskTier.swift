import Foundation

/// The five-tier safety classification that defines Reclaim's trust moat.
/// Tiers are ordered from safest to most protected. The tier determines
/// what the product is *allowed* to do — not what it *can* do.
public enum RiskTier: String, Codable, CaseIterable, Sendable, Comparable {
    /// Regenerable: caches, previews, downloaded installers' staging, temp clones.
    /// Allowed: one-click cleanup after app/process checks.
    case green

    /// Reversible local data: re-downloadable copies, quarantineable leftovers.
    /// Allowed: quarantine by default, with a rollback window.
    case blue

    /// History or workflow state: Cursor conversations, sessions, useful logs.
    /// Allowed: explain impact, require explicit per-item selection.
    case yellow

    /// Personal or cloud-synced content: Messages attachments, media, documents.
    /// Allowed: never auto-delete. Present precise device/cloud consequences.
    case orange

    /// System-protected or uncertain: Data Vaults, swap, sealed assets, mounts.
    /// Allowed: nothing. Use a supported manager or leave untouched.
    case red

    public var displayName: String {
        switch self {
        case .green:  return "Green — Regenerable"
        case .blue:   return "Blue — Reversible local data"
        case .yellow: return "Yellow — History or workflow state"
        case .orange: return "Orange — Personal or cloud-synced"
        case .red:    return "Red — System-protected"
        }
    }

    /// Whether the engine may ever execute an automated action for this tier.
    /// V1 automates Green only (founder decision, section 16).
    public var automatable: Bool { self == .green }

    private var rank: Int {
        switch self {
        case .green: 0; case .blue: 1; case .yellow: 2; case .orange: 3; case .red: 4
        }
    }

    public static func < (lhs: RiskTier, rhs: RiskTier) -> Bool { lhs.rank < rhs.rank }
}
