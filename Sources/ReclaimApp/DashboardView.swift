import SwiftUI
import ReclaimCore

struct DashboardView: View {
    @EnvironmentObject var model: ScanModel

    var body: some View {
        Group {
            if let report = model.report {
                ReportView(report: report)
            } else if model.scanning {
                ScanningView(current: model.currentRecipe)
            } else {
                WelcomeView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.runScan()
                } label: {
                    Label(model.report == nil ? "Scan" : "Rescan", systemImage: "magnifyingglass")
                }
                .disabled(model.scanning)
            }
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @EnvironmentObject var model: ScanModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "internaldrive")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Your Mac is not full. Your tools are messy.")
                .font(.title2.weight(.semibold))
            Text("Reclaim shows exactly what Cursor, Xcode, npm, browsers, and old build tools left behind — then safely explains what can be cleared without touching your code.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button("Run Read-Only Scan") { model.runScan() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Text("A scan never modifies your Mac. Cleanup is a separate, explicit step.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Scanning

struct ScanningView: View {
    let current: String
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Scanning (read-only)…").font(.headline)
            Text(current).font(.caption).foregroundStyle(.secondary)
                .frame(height: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Report

struct ReportView: View {
    let report: ScanReport

    private var tiers: [(RiskTier, [Finding])] {
        RiskTier.allCases.compactMap { tier in
            let items = report.findings.filter { $0.riskTier == tier }
            return items.isEmpty ? nil : (tier, items)
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    SummaryCard(
                        title: "Recoverable now",
                        value: ByteFormatter.string(report.recoverableNowBytes),
                        subtitle: "Green tier · apps closed",
                        color: .green
                    )
                    SummaryCard(
                        title: "Review for more",
                        value: ByteFormatter.string(report.reviewBytes),
                        subtitle: "History & personal content",
                        color: .yellow
                    )
                    SummaryCard(
                        title: "Free space",
                        value: ByteFormatter.string(report.volumeFreeBytes),
                        subtitle: "of \(ByteFormatter.string(report.volumeTotalBytes))",
                        color: .blue
                    )
                }
                .listRowSeparator(.hidden)
            }

            ForEach(tiers, id: \.0) { tier, findings in
                Section(header: TierHeader(tier: tier, findings: findings)) {
                    ForEach(findings) { finding in
                        FindingRow(finding: finding)
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.bold)).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TierHeader: View {
    let tier: RiskTier
    let findings: [Finding]

    private var tierColor: Color {
        switch tier {
        case .green: .green; case .blue: .blue; case .yellow: .yellow
        case .orange: .orange; case .red: .red
        }
    }

    var body: some View {
        HStack {
            Circle().fill(tierColor).frame(width: 8, height: 8)
            Text(tier.displayName)
            Spacer()
            Text(ByteFormatter.string(findings.reduce(0) { $0 + $1.allocatedBytes }))
                .monospacedDigit()
        }
    }
}

/// Recommendation card anatomy per plan §12: size, location, creator,
/// risk class, impact, recurrence, action method.
struct FindingRow: View {
    let finding: Finding
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text(finding.explanation)
                Text("Impact: \(finding.impact)").foregroundStyle(.secondary)
                Text("Recurrence: \(finding.recurrence)").foregroundStyle(.secondary)
                HStack {
                    Text("Action: \(actionLabel)").font(.caption.weight(.medium))
                    if let modified = finding.lastModified {
                        Text("· Modified \(modified.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                if !finding.skippedProtectedPaths.isEmpty {
                    Label("\(finding.skippedProtectedPaths.count) protected path(s) skipped — macOS said no, and Reclaim listens.",
                          systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(finding.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .font(.callout)
            .padding(.vertical, 4)
        } label: {
            HStack {
                Text(finding.displayName)
                if finding.blockingAppRunning {
                    Label("app running", systemImage: "pause.circle")
                        .font(.caption).foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
                Spacer()
                Text(ByteFormatter.string(finding.allocatedBytes))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private var actionLabel: String {
        switch finding.action {
        case .quarantine: "Quarantine (reversible)"
        case .supportedCLI: "Official tool command"
        case .reviewOnly: "Manual review only"
        case .none: "Report only — never touched"
        }
    }
}
