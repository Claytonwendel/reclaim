import SwiftUI
import ReclaimCore

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(AppModel.Section.allCases, selection: $model.section) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { busyBanner }
        }
        .task { model.loadQuarantine() }
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .scan:       ScanView()
        case .quarantine: QuarantineView()
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().padding(.bottom, 6)
            Text("Reclaimed all-time")
                .font(.caption2).foregroundStyle(.secondary)
            Text(Fmt.bytes(model.lifetimeReclaimed))
                .font(.callout.weight(.semibold)).foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    @ViewBuilder private var busyBanner: some View {
        if let busy = model.busy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(busy).font(.callout)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 8, y: 2)
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Shared components

/// A big number card for the dashboard headers.
struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    var color: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// A colored tier dot + label.
struct TierBadge: View {
    let tier: RiskTier
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tier.color).frame(width: 8, height: 8)
            Text(tier.displayName)
        }
    }
}

/// The empty/prompt state shown before a section has been run.
struct SectionPrompt: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String
    var loading: Bool = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            if loading {
                ProgressView().controlSize(.large)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
