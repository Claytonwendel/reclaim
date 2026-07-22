import Foundation

/// One user-facing slice of what's using the disk. Bytes are physical
/// (allocated) size, matching how the volume actually accounts for space.
public struct StorageCategory: Codable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String          // stable id, e.g. "applications"
    public let name: String         // "Applications"
    public let bytes: Int64
    public let fileCount: Int
    public let symbol: String       // SF Symbol
    public let detail: String       // plain-language description
    /// False for the reconciling "System & other" remainder — it's computed
    /// from the disk total, not walked file-by-file.
    public let itemized: Bool

    public init(key: String, name: String, bytes: Int64, fileCount: Int,
                symbol: String, detail: String, itemized: Bool) {
        self.key = key
        self.name = name
        self.bytes = bytes
        self.fileCount = fileCount
        self.symbol = symbol
        self.detail = detail
        self.itemized = itemized
    }
}

/// The output of a "My Mac" scan: an honest, whole-disk picture of where the
/// space goes. Unlike the recipe scan (what's *removable*), this shows
/// *everything* — and is anchored to the volume's real used bytes.
public struct MacStorageReport: Codable, Sendable {
    public let scannedAt: Date
    public let hostname: String
    /// Volume capacity — the "of Y" in "X available of Y".
    public let capacityBytes: Int64
    /// Space the OS reports as available (matches Finder / About This Mac).
    public let freeBytes: Int64
    /// capacity − free. The number every category is reconciled against.
    public let usedBytes: Int64
    /// Occupied-but-reclaimable space (caches/snapshots the OS can evict).
    public let purgeableBytes: Int64
    /// Categories, largest first. Always includes a "System & other" remainder
    /// so the itemized slices + remainder sum EXACTLY to usedBytes.
    public let categories: [StorageCategory]
    /// Sum of the walked (itemized) categories — what Reclaim could actually see.
    public let measuredBytes: Int64
    /// True in the rare case our walk measured more than the disk reports used
    /// (APFS clones / hardlinks counted under multiple folders). Then there is
    /// no remainder and the picture is approximate — surfaced honestly.
    public let overMeasured: Bool
    public let totalFileCount: Int
    public let snapshots: SnapshotStatus
    /// Whether Reclaim could see TCC-protected data during the walk. When
    /// denied, protected files are silently skipped and land in the unitemized
    /// remainder — so the map under-itemizes until FDA is granted.
    public let fullDiskAccess: FullDiskAccess.Status
    public let elapsedSeconds: Double

    public var usedFraction: Double {
        capacityBytes > 0 ? Double(usedBytes) / Double(capacityBytes) : 0
    }

    public init(scannedAt: Date, hostname: String, capacityBytes: Int64,
                freeBytes: Int64, usedBytes: Int64, purgeableBytes: Int64,
                categories: [StorageCategory], measuredBytes: Int64,
                overMeasured: Bool, totalFileCount: Int,
                snapshots: SnapshotStatus,
                fullDiskAccess: FullDiskAccess.Status,
                elapsedSeconds: Double) {
        self.scannedAt = scannedAt
        self.hostname = hostname
        self.capacityBytes = capacityBytes
        self.freeBytes = freeBytes
        self.usedBytes = usedBytes
        self.purgeableBytes = purgeableBytes
        self.categories = categories
        self.measuredBytes = measuredBytes
        self.overMeasured = overMeasured
        self.totalFileCount = totalFileCount
        self.snapshots = snapshots
        self.fullDiskAccess = fullDiskAccess
        self.elapsedSeconds = elapsedSeconds
    }
}

/// Builds the "My Mac" storage map: a whole-disk breakdown that always
/// reconciles to the volume's real used space.
///
/// Accuracy contract: the ONE number we can state with certainty is the
/// volume's used bytes (capacity − free). We walk everything readable under
/// home + the Applications folders, classify each file into a familiar
/// category, then compute the gap `used − measured` as a single honest
/// "System & other (not itemized)" slice. So the categories always add up to
/// the disk's actual usage — never a fabricated total. Read-only, always.
public struct MacStorageMap: Sendable {
    public let home: String
    public let applicationRoots: [String]
    /// Test seams: when nil, the real volume is probed.
    let capacityOverride: Int64?
    let freeOverride: Int64?
    let rawFreeOverride: Int64?

    public init(home: String = NSHomeDirectory(),
                applicationRoots: [String] = ["/Applications",
                                              NSHomeDirectory() + "/Applications"]) {
        self.init(home: home, applicationRoots: applicationRoots,
                  capacityOverride: nil, freeOverride: nil, rawFreeOverride: nil)
    }

    init(home: String, applicationRoots: [String],
         capacityOverride: Int64?, freeOverride: Int64?, rawFreeOverride: Int64?) {
        self.home = home
        self.applicationRoots = applicationRoots
        self.capacityOverride = capacityOverride
        self.freeOverride = freeOverride
        self.rawFreeOverride = rawFreeOverride
    }

    // MARK: - Category taxonomy

    struct CategorySpec { let key, name, symbol, detail: String }

    /// Display metadata, keyed by the id `classify` returns. Order here is the
    /// tiebreak when two categories are the same size; real order is by bytes.
    static let specs: [CategorySpec] = [
        .init(key: "applications", name: "Applications", symbol: "app.badge",
              detail: "Apps installed in your Applications folders."),
        .init(key: "photos", name: "Photos & Images", symbol: "photo.on.rectangle",
              detail: "Your Pictures folder, including Photos libraries."),
        .init(key: "movies", name: "Movies & Video", symbol: "film",
              detail: "Your Movies folder and video files."),
        .init(key: "music", name: "Music & Audio", symbol: "music.note",
              detail: "Your Music folder and audio libraries."),
        .init(key: "documents", name: "Documents & Desktop", symbol: "doc.text",
              detail: "Files on your Desktop and in Documents."),
        .init(key: "downloads", name: "Downloads", symbol: "arrow.down.circle",
              detail: "Everything in your Downloads folder."),
        .init(key: "developer", name: "Developer & Caches", symbol: "hammer",
              detail: "Xcode data, build output, and package-manager caches."),
        .init(key: "mail", name: "Mail", symbol: "envelope",
              detail: "Locally stored mail and attachments."),
        .init(key: "messages", name: "Messages", symbol: "message",
              detail: "Messages history and attachments."),
        .init(key: "appdata", name: "App Data & Support", symbol: "shippingbox",
              detail: "App containers, Application Support, and preferences."),
        .init(key: "trash", name: "Trash", symbol: "trash",
              detail: "Items in the Trash — still using space until emptied."),
        .init(key: "userother", name: "Other User Files", symbol: "folder",
              detail: "Other files in your home folder."),
        .init(key: "system", name: "System & Other", symbol: "gearshape",
              detail: "macOS itself, system data, other user accounts, and space "
                    + "outside your home folder that Reclaim can't itemize without "
                    + "deeper access. Computed so the total matches your disk exactly."),
    ]

    static func spec(_ key: String) -> CategorySpec {
        specs.first { $0.key == key } ?? specs.last!
    }

    /// Hidden home directories that are really developer caches, not documents.
    static let devDotDirs = [".npm", ".cache", ".gradle", ".docker", ".m2",
                             ".cargo", ".rustup", ".yarn", ".gem", ".cocoapods",
                             ".pnpm-store", ".bun", ".deno", ".nuget"]

    /// Maps an absolute path to a category key. Pure and order-sensitive:
    /// most-specific rules win. Public-ish (internal) so it can be unit-tested.
    static func classify(_ rawPath: String, home rawHome: String) -> String {
        // Normalize the /private prefix: macOS directory enumeration emits
        // /private/var/… while home may be recorded as /var/… (and /tmp, /etc).
        // Real homes under /Users are untouched.
        func strip(_ p: String) -> String {
            p.hasPrefix("/private/") ? String(p.dropFirst("/private".count)) : p
        }
        let path = strip(rawPath), home = strip(rawHome)
        func under(_ sub: String) -> Bool {
            let base = home + "/" + sub
            return path == base || path.hasPrefix(base + "/")
        }
        if under(".Trash") { return "trash" }
        if under("Library/Developer") || under("Library/Caches") { return "developer" }
        if under("Library/Mail") { return "mail" }
        if under("Library/Messages") { return "messages" }
        if under("Library") { return "appdata" }
        if under("Pictures") { return "photos" }
        if under("Movies") { return "movies" }
        if under("Music") { return "music" }
        if under("Documents") || under("Desktop") { return "documents" }
        if under("Downloads") { return "downloads" }
        for d in devDotDirs where under(d) { return "developer" }
        return "userother"
    }

    // MARK: - Run

    public func run(progress: (@Sendable (Int) -> Void)? = nil) -> MacStorageReport {
        let start = Date()
        let facts = volumeFacts()
        let used = max(0, facts.capacity - facts.importantFree)
        let purgeable = max(0, facts.importantFree - facts.rawFree)

        // Canonicalize home so path-prefix classification is symlink-safe
        // (e.g. /var → /private/var). The enumerator inherits this resolved
        // prefix, so per-file paths line up with `canonicalHome`.
        let canonicalHome = URL(fileURLWithPath: home).resolvingSymlinksInPath().path

        var bytesByKey: [String: Int64] = [:]
        var countByKey: [String: Int] = [:]
        var totalFiles = 0

        let sizeKeys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey,
        ]

        func walk(_ root: String, forceKey: String?) {
            let url = URL(fileURLWithPath: root).resolvingSymlinksInPath()
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return }
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: Array(sizeKeys),
                options: [], errorHandler: { _, _ in true })  // skip unreadable, keep going
            while let item = enumerator?.nextObject() as? URL {
                guard let v = try? item.resourceValues(forKeys: sizeKeys),
                      v.isRegularFile == true else { continue }
                let bytes = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                let key = forceKey ?? Self.classify(item.path, home: canonicalHome)
                bytesByKey[key, default: 0] += bytes
                countByKey[key, default: 0] += 1
                totalFiles += 1
                if totalFiles % 100_000 == 0 { progress?(totalFiles) }
            }
        }

        walk(canonicalHome, forceKey: nil)
        for appRoot in applicationRoots { walk(appRoot, forceKey: "applications") }

        let measured = bytesByKey.values.reduce(0, +)
        let overMeasured = measured > used && used > 0

        let categories = Self.buildCategories(
            bytesByKey: bytesByKey, countByKey: countByKey,
            usedBytes: used, measuredBytes: measured)

        return MacStorageReport(
            scannedAt: start,
            hostname: ProcessInfo.processInfo.hostName,
            capacityBytes: facts.capacity,
            freeBytes: facts.importantFree,
            usedBytes: used,
            purgeableBytes: purgeable,
            categories: categories,
            measuredBytes: measured,
            overMeasured: overMeasured,
            totalFileCount: totalFiles,
            snapshots: SnapshotProbe.status(),
            fullDiskAccess: FullDiskAccess.status(),
            elapsedSeconds: Date().timeIntervalSince(start))
    }

    /// Turns raw per-key byte tallies into display categories plus the
    /// reconciling remainder. Invariant: when `measured <= used`, the returned
    /// categories' bytes sum to EXACTLY `usedBytes`. Kept pure for testing.
    static func buildCategories(bytesByKey: [String: Int64],
                                countByKey: [String: Int],
                                usedBytes: Int64,
                                measuredBytes: Int64) -> [StorageCategory] {
        var out: [StorageCategory] = bytesByKey
            .filter { $0.value > 0 }
            .map { key, bytes in
                let s = spec(key)
                return StorageCategory(key: key, name: s.name, bytes: bytes,
                                       fileCount: countByKey[key] ?? 0,
                                       symbol: s.symbol, detail: s.detail, itemized: true)
            }

        // The honest gap: everything on the disk we couldn't walk (System,
        // other users, anything outside home). Clamped at 0 — if we somehow
        // measured more than the disk reports used (clones/hardlinks), there's
        // no remainder to show and `overMeasured` flags the approximation.
        let remainder = max(0, usedBytes - measuredBytes)
        if remainder > 0 {
            let s = spec("system")
            out.append(StorageCategory(key: s.key, name: s.name, bytes: remainder,
                                       fileCount: 0, symbol: s.symbol,
                                       detail: s.detail, itemized: false))
        }
        return out.sorted { $0.bytes > $1.bytes }
    }

    // MARK: - Volume facts

    struct VolumeFacts { let capacity: Int64; let importantFree: Int64; let rawFree: Int64 }

    private func volumeFacts() -> VolumeFacts {
        if let c = capacityOverride, let f = freeOverride {
            return VolumeFacts(capacity: c, importantFree: f, rawFree: rawFreeOverride ?? f)
        }
        let url = URL(fileURLWithPath: home)
        let v = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        return VolumeFacts(
            capacity: Int64(v?.volumeTotalCapacity ?? 0),
            importantFree: v?.volumeAvailableCapacityForImportantUsage ?? 0,
            rawFree: Int64(v?.volumeAvailableCapacity ?? 0))
    }
}
