import SwiftUI
import ReclaimCore
import QuickLookThumbnailing

/// Generates real file thumbnails (image/video previews, document pages) via
/// QuickLook — the same previews Finder shows. Falls back to the file-type icon.
enum Thumbnails {
    static func generate(_ path: String, size: CGFloat = 96) async -> NSImage? {
        let req = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: CGSize(width: size, height: size),
            scale: 2,
            representationTypes: .thumbnail)
        return await withCheckedContinuation { cont in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
                cont.resume(returning: rep?.nsImage)
            }
        }
    }
}

/// A thumbnail tile that loads asynchronously, showing the file-type icon
/// until the real preview arrives.
struct ThumbView: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.5))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable().aspectRatio(contentMode: .fit).padding(8)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .task(id: path) { image = await Thumbnails.generate(path) }
    }
}

/// The media browser: drill into a pile-up, filter by size and age, then
/// select-all-matching and reclaim in two clicks. This filter→select-all
/// pattern is the template for any category with lots of similar files.
struct ClusterDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let cluster: Cluster

    @State private var selected: Set<String> = []
    @State private var sort: Sort = .largest
    @State private var sizeFilter: SizeFilter = .any
    @State private var ageFilter: AgeFilter = .any

    enum Sort: String, CaseIterable, Identifiable {
        case largest = "Largest", oldest = "Oldest", newest = "Newest"
        var id: String { rawValue }
    }

    /// Files matching the active size + age filters, in the chosen order.
    private var filtered: [ClusterFile] {
        let now = Date()
        let matched = cluster.files.filter { f in
            f.bytes >= sizeFilter.minBytes && ageFilter.matches(f.modified, now: now)
        }
        switch sort {
        case .largest: return matched.sorted { $0.bytes > $1.bytes }
        case .oldest:  return matched.sorted { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
        case .newest:  return matched.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        }
    }
    private var filteredBytes: Int64 { filtered.reduce(0) { $0 + $1.bytes } }
    private var selectedBytes: Int64 {
        cluster.files.filter { selected.contains($0.path) }.reduce(0) { $0 + $1.bytes }
    }
    private var allFilteredSelected: Bool {
        !filtered.isEmpty && filtered.allSatisfy { selected.contains($0.path) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider()
            if filtered.isEmpty {
                ContentUnavailableView("Nothing matches these filters",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Loosen the size or age filter."))
                    .frame(maxHeight: .infinity)
            } else {
                List(filtered) { file in
                    FileRow(file: file, isOn: Binding(
                        get: { selected.contains(file.path) },
                        set: { on in if on { selected.insert(file.path) } else { selected.remove(file.path) } }))
                }
                .listStyle(.inset)
            }
            Divider()
            footer
        }
        .frame(minWidth: 580, minHeight: 560)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(cluster.category) in \(cluster.directory)").font(.headline)
                Text("\(cluster.count) files · \(Fmt.bytes(cluster.totalBytes))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $sort) {
                ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(width: 210)
            Button("Done") { dismiss() }
        }
        .padding(14)
    }

    /// The reusable filter row: size + age menus, plus a live "select all
    /// matching" that makes bulk cleanup two clicks.
    private var filterBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(SizeFilter.allCases) { f in Button(f.rawValue) { sizeFilter = f } }
            } label: {
                Label(sizeFilter == .any ? "Size" : sizeFilter.rawValue, systemImage: "arrow.up.arrow.down.circle")
            }.menuStyle(.borderlessButton).fixedSize()

            Menu {
                ForEach(AgeFilter.allCases) { f in Button(f.rawValue) { ageFilter = f } }
            } label: {
                Label(ageFilter == .any ? "Age" : ageFilter.rawValue, systemImage: "calendar")
            }.menuStyle(.borderlessButton).fixedSize()

            if sizeFilter != .any || ageFilter != .any {
                Button {
                    sizeFilter = .any; ageFilter = .any
                } label: { Text("Clear").font(.caption) }.buttonStyle(.link)
            }

            Spacer()

            Text("\(filtered.count) match · \(Fmt.bytes(filteredBytes))")
                .font(.caption).foregroundStyle(.secondary)
            Button(allFilteredSelected ? "Deselect all" : "Select all matching") {
                if allFilteredSelected { filtered.forEach { selected.remove($0.path) } }
                else { filtered.forEach { selected.insert($0.path) } }
            }
            .disabled(filtered.isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.quaternary.opacity(0.25))
    }

    private var footer: some View {
        HStack {
            Text("\(selected.count) selected · \(Fmt.bytes(selectedBytes))")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button {
                let targets = cluster.files
                    .filter { selected.contains($0.path) }
                    .map { CleanupTarget(path: $0.path, riskTier: cluster.riskTier, source: "review") }
                model.reclaim(targets)
                dismiss()
            } label: {
                Text("Reclaim \(Fmt.bytes(selectedBytes))").frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty || model.busy != nil)
        }
        .padding(14)
    }
}

/// Size threshold filter — reusable across any file-heavy category.
enum SizeFilter: String, CaseIterable, Identifiable {
    case any = "Any size", m5 = "≥ 5 MB", m25 = "≥ 25 MB", m100 = "≥ 100 MB", m500 = "≥ 500 MB", g1 = "≥ 1 GB"
    var id: String { rawValue }
    var minBytes: Int64 {
        switch self {
        case .any: 0
        case .m5:   5 * 1024 * 1024
        case .m25:  25 * 1024 * 1024
        case .m100: 100 * 1024 * 1024
        case .m500: 500 * 1024 * 1024
        case .g1:   1024 * 1024 * 1024
        }
    }
}

/// Age threshold filter — "older than N".
enum AgeFilter: String, CaseIterable, Identifiable {
    case any = "Any age", d30 = "Over 30 days", d90 = "Over 90 days",
         m6 = "Over 6 months", y1 = "Over 1 year", y2 = "Over 2 years"
    var id: String { rawValue }
    private var minDays: Int? {
        switch self {
        case .any: nil
        case .d30: 30; case .d90: 90; case .m6: 182; case .y1: 365; case .y2: 730
        }
    }
    func matches(_ modified: Date?, now: Date) -> Bool {
        guard let minDays else { return true }
        guard let modified else { return false }   // unknown date fails an age filter
        return now.timeIntervalSince(modified) >= Double(minDays) * 86400
    }
}

private struct FileRow: View {
    let file: ClusterFile
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.checkbox)
            ThumbView(path: file.path)
            VStack(alignment: .leading, spacing: 2) {
                Text((file.path as NSString).lastPathComponent).fontWeight(.medium).lineLimit(1)
                Text(dateLine).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Text(Fmt.bytes(file.bytes)).monospacedDigit().foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
            } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Reveal in Finder")
        }
        .padding(.vertical, 2)
    }

    private var dateLine: String {
        guard let d = file.modified else { return "date unknown" }
        let days = Int(Date().timeIntervalSince(d) / 86400)
        return "\(d.formatted(date: .abbreviated, time: .omitted)) · \(days) days ago"
    }
}
