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
    print("  Review for more (Yellow + Orange):     \(ByteFormatter.string(report.reviewBytes))")
    if report.snapshots.mayPinDeletedBlocks {
        print("  ⧗ \(report.snapshots.count) APFS local snapshot(s) present — freed space may not appear")
        print("    immediately after cleanup; snapshots expire within ~24h.")
    }
    print("")

    // ── Findings by tier ──────────────────────────────────────
    for tier in RiskTier.allCases {
        let items = report.findings.filter { $0.riskTier == tier }
        guard !items.isEmpty else { continue }
        let total = items.reduce(0) { $0 + $1.allocatedBytes }
        print("── \(tierBadge(tier)) \(tier.displayName) · \(ByteFormatter.string(total))")
        for f in items {
            let blocked = f.blockingAppRunning ? "  ⏸ app running — quit before cleanup" : ""
            let skipped = f.skippedProtectedPaths.isEmpty ? "" : "  🔒 \(f.skippedProtectedPaths.count) protected path(s) skipped"
            // Sparse files (Docker.raw, VM disks): apparent size far exceeds
            // real allocation — report the honest number, note the illusion.
            let sparse = f.apparentBytes > f.allocatedBytes * 2
                ? "  ◱ sparse — appears as \(ByteFormatter.string(f.apparentBytes))" : ""
            print(String(format: "  %10@  %@%@%@%@",
                         ByteFormatter.string(f.allocatedBytes) as NSString,
                         f.displayName, blocked, skipped, sparse))
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

case "sweep":
    // Whole-volume attribution sweep: where ALL the bytes are, and how much
    // of the disk the recipe catalog can currently explain.
    var depth = 3
    if let idx = args.firstIndex(of: "--depth"), let d = Int(args[args.index(after: idx)]) {
        depth = d
    }
    if !wantsJSON {
        FileHandle.standardError.write(Data("Reclaim sweep (read-only) — walking \(NSHomeDirectory())…\n".utf8))
    }
    let sweep = VolumeSweep(depth: depth)
    let report = sweep.run(progress: { files in
        FileHandle.standardError.write(Data("  \(files / 1000)k files…\r".utf8))
    })

    if wantsJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(data: try encoder.encode(report), encoding: .utf8)!)
        exit(0)
    }

    print("")
    print("═══ Reclaim Sweep · \(report.root) ═══")
    print("\(ByteFormatter.string(report.totalAllocatedBytes)) allocated · \(report.totalFileCount) files · \(String(format: "%.1f", report.elapsedSeconds))s")
    if report.skippedProtectedCount > 0 {
        print("🔒 \(report.skippedProtectedCount) protected location(s) skipped — macOS said no, and Reclaim listens.")
    }
    let pct = report.totalAllocatedBytes > 0
        ? Double(report.explainedBytes) / Double(report.totalAllocatedBytes) * 100 : 0
    print("Recipe coverage: \(ByteFormatter.string(report.explainedBytes)) explained (\(String(format: "%.0f", pct))%) · \(ByteFormatter.string(report.unexplainedBytes)) unexplained\n")

    let home = NSHomeDirectory()
    for entry in report.entries {
        let rel = entry.path.hasPrefix(home) ? "~" + entry.path.dropFirst(home.count) : entry.path
        let indent = String(repeating: "  ", count: max(0, rel.split(separator: "/").count - 1))
        let tag = entry.explainedBy.map { "  ✓ \($0)" } ?? ""
        print(String(format: "  %10@  %@%@%@",
                     ByteFormatter.string(entry.allocatedBytes) as NSString,
                     indent, rel, tag))
    }
    print("\nDirs ≥ \(ByteFormatter.string(500 * 1024 * 1024)) shown. ✓ = at/below a recipe path; the unexplained rest is recipe-library work to do.")

default:
    print("usage: reclaim [scan|sweep|recipes] [--json] [--verbose] [--depth N]")
    exit(64)
}
