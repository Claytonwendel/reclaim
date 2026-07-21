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

case "orphans":
    // Leftover app data whose owning app is no longer installed.
    if !wantsJSON {
        FileHandle.standardError.write(Data("Reclaim orphan scan (read-only) — matching Library data against installed apps…\n".utf8))
    }
    let scanner = OrphanScanner()
    let orphans = scanner.scan()

    if wantsJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(data: try encoder.encode(orphans), encoding: .utf8)!)
        exit(0)
    }

    let likely = orphans.filter { $0.confidence == .likelyOrphan }
    let unattributed = orphans.filter { $0.confidence == .unattributed }
    let likelyTotal = likely.reduce(0) { $0 + $1.allocatedBytes }

    print("")
    print("═══ Reclaim Orphans · leftover app data ═══")
    print("🔵 Likely orphaned (owning app not installed): \(ByteFormatter.string(likelyTotal)) across \(likely.count) item(s)")
    print("These are Blue-tier — reversible via quarantine. Owning app appears gone.\n")

    let home = NSHomeDirectory()
    func row(_ o: Orphan) {
        let rel = o.path.hasPrefix(home) ? "~" + o.path.dropFirst(home.count) : o.path
        let age = o.lastModified.map { "  · last used \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        print(String(format: "  %10@  %@%@", ByteFormatter.string(o.allocatedBytes) as NSString, rel, age))
    }
    for o in likely { row(o) }

    if !unattributed.isEmpty {
        let uTotal = unattributed.reduce(0) { $0 + $1.allocatedBytes }
        print("\n── ❓ Unattributed (couldn't confidently match to an app): \(ByteFormatter.string(uTotal))")
        print("   Review only — NOT called orphaned. Could belong to a shared component.")
        for o in unattributed.prefix(15) { row(o) }
        if unattributed.count > 15 { print("   … and \(unattributed.count - 15) more") }
    }
    if orphans.isEmpty {
        print("No orphaned leftovers found above threshold. Either tidy, or apps live where the inventory didn't look.")
    }
    print("\nSafety: Apple/system components are allowlisted and never flagged.")

case "review":
    // The judgment layer: personal files you might not want anymore.
    if !wantsJSON {
        FileHandle.standardError.write(Data("Reclaim review (read-only) — looking for personal files you may not need…\n".utf8))
    }
    let judge = JudgmentScanner()
    let report = judge.scan()

    if wantsJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(data: try encoder.encode(report), encoding: .utf8)!)
        exit(0)
    }

    func reasonTitle(_ r: SuggestionReason) -> String {
        switch r {
        case .oldAndLarge: "Large & untouched for a while"
        case .veryLarge: "Your biggest files"
        case .duplicate: "Exact duplicates"
        case .oldScreenRecording: "Old screen recordings"
        case .oldScreenshot: "Old screenshots"
        case .installerForInstalledApp: "Installers for apps you already have"
        case .oldDownload: "Old downloads"
        case .oldDeviceBackup: "iPhone/iPad backups"
        case .oldAttachment: "Old attachments"
        }
    }

    let home = NSHomeDirectory()
    let clusterTotal = report.clusters.reduce(0) { $0 + $1.totalBytes }
    print("")
    print("═══ Reclaim Review · personal files you might not need ═══")
    print("We think you could reclaim up to \(ByteFormatter.string(report.totalBytes + clusterTotal)) here.")
    print("Everything below is YOUR content — nothing is ever removed without you choosing it.\n")

    // Clusters first — the "death by a thousand cuts" accumulations.
    if !report.clusters.isEmpty {
        print("▓▓ Accumulations (many small files adding up) ▓▓")
        for c in report.clusters {
            print("── \(c.category) in \(c.directory) · \(ByteFormatter.string(c.totalBytes)) · \(c.count) files")
            print("   \(c.rationale)")
            if verbose, !c.samples.isEmpty {
                print("   e.g. \(c.samples.joined(separator: ", "))")
            }
        }
        print("")
    }

    for (reason, items) in report.grouped() {
        let total = items.reduce(0) { $0 + $1.sizeBytes }
        print("── \(reasonTitle(reason)) · \(ByteFormatter.string(total)) · \(items.count) item(s)")
        for s in items.prefix(10) {
            let rel = s.path.hasPrefix(home) ? "~" + s.path.dropFirst(home.count) : s.path
            let stars = String(repeating: "●", count: Int((s.confidence * 3).rounded()))
            print(String(format: "  %10@  %@  %@", ByteFormatter.string(s.sizeBytes) as NSString, rel, stars))
            if verbose { print("              \(s.rationale)") }
        }
        if items.count > 10 { print("  … and \(items.count - 10) more") }
        print("")
    }
    if report.suggestions.isEmpty && report.clusters.isEmpty {
        print("Nothing jumped out. Your personal folders look tidy (or are smaller than the thresholds).")
    } else {
        print("● = how confident we are you won't miss it. Run with --verbose to see our reasoning per file.")
    }

default:
    print("usage: reclaim [scan|sweep|orphans|review|recipes] [--json] [--verbose] [--depth N]")
    exit(64)
}
