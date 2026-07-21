import Foundation
import ReclaimCore

// reclaim — read-only storage scan (Phase 0 concierge tool)
//
//   reclaim scan            human-readable report
//   reclaim scan --json     machine-readable report (for the ledger / app)
//   reclaim recipes         list the recipe catalog
//
// This tool NEVER deletes anything. It scans, classifies, and explains.

let args = CommandLine.arguments.dropFirst()
let command = args.first ?? "scan"
let wantsJSON = args.contains("--json")
let verbose = args.contains("--verbose") || args.contains("-v")

func tierBadge(_ tier: RiskTier) -> String {
    switch tier {
    case .green: "🟢"; case .blue: "🔵"; case .yellow: "🟡"; case .orange: "🟠"; case .red: "🔴"
    }
}

switch command {
case "recipes":
    print("Reclaim recipe catalog — \(RecipeCatalog.all.count) recipes\n")
    for group in Dictionary(grouping: RecipeCatalog.all, by: \.group).sorted(by: { $0.key < $1.key }) {
        print("── \(group.key)")
        for r in group.value {
            print("  \(tierBadge(r.riskTier)) \(r.id) — \(r.displayName)")
        }
    }

case "scan":
    if !wantsJSON {
        FileHandle.standardError.write(Data("Reclaim read-only scan — nothing will be modified.\n".utf8))
    }
    let scanner = StorageScanner()
    var progress: (@Sendable (String) -> Void)? = nil
    if verbose {
        progress = { name in
            FileHandle.standardError.write(Data("  scanning: \(name)\n".utf8))
        }
    }
    let report = scanner.scan(progress: progress)

    if wantsJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        print(String(data: data, encoding: .utf8)!)
        exit(0)
    }

    // ── Header ────────────────────────────────────────────────
    print("")
    print("═══ Reclaim Scan · \(report.hostname) ═══")
    print("Volume: \(ByteFormatter.string(report.volumeFreeBytes)) free of \(ByteFormatter.string(report.volumeTotalBytes))")
    print("Scan took \(String(format: "%.1f", report.elapsedSeconds))s · \(report.findings.count) findings\n")

    // ── Dashboard numbers (section 12: home dashboard panels) ─
    print("  Recoverable now (Green, apps closed):  \(ByteFormatter.string(report.recoverableNowBytes))")
    print("  Review for more (Yellow + Orange):     \(ByteFormatter.string(report.reviewBytes))\n")

    // ── Findings by tier ──────────────────────────────────────
    for tier in RiskTier.allCases {
        let items = report.findings.filter { $0.riskTier == tier }
        guard !items.isEmpty else { continue }
        let total = items.reduce(0) { $0 + $1.allocatedBytes }
        print("── \(tierBadge(tier)) \(tier.displayName) · \(ByteFormatter.string(total))")
        for f in items {
            let blocked = f.blockingAppRunning ? "  ⏸ app running — quit before cleanup" : ""
            let skipped = f.skippedProtectedPaths.isEmpty ? "" : "  🔒 \(f.skippedProtectedPaths.count) protected path(s) skipped"
            print(String(format: "  %10@  %@%@%@",
                         ByteFormatter.string(f.allocatedBytes) as NSString,
                         f.displayName, blocked, skipped))
            print("              \(f.path)")
            if verbose {
                print("              \(f.explanation)")
                print("              Impact: \(f.impact)")
            }
        }
        print("")
    }

    if report.findings.isEmpty {
        print("No findings above thresholds. This Mac is clean — or permissions are limiting the scan.")
        print("Tip: grant Full Disk Access to your terminal to scan Messages and app containers.")
    }

default:
    print("usage: reclaim [scan|recipes] [--json] [--verbose]")
    exit(64)
}
