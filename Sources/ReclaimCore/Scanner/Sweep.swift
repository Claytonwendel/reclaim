import Foundation

/// A node in the whole-volume sweep: a directory, its total allocated size,
/// and whether the recipe catalog explains it.
public struct SweepEntry: Codable, Sendable {
    public let path: String
    public let allocatedBytes: Int64
    public let fileCount: Int
    /// Recipe ID whose paths contain this directory, if any.
    public let explainedBy: String?

    public init(path: String, allocatedBytes: Int64, fileCount: Int, explainedBy: String?) {
        self.path = path
        self.allocatedBytes = allocatedBytes
        self.fileCount = fileCount
        self.explainedBy = explainedBy
    }
}

public struct SweepReport: Codable, Sendable {
    public let root: String
    public let totalAllocatedBytes: Int64
    public let totalFileCount: Int
    /// Bytes living under any recipe path — counted per file, no double counting.
    public let explainedBytes: Int64
    public let entries: [SweepEntry]          // sorted largest-first
    public let skippedProtectedCount: Int
    public let elapsedSeconds: Double

    public init(root: String, totalAllocatedBytes: Int64, totalFileCount: Int,
                explainedBytes: Int64, entries: [SweepEntry],
                skippedProtectedCount: Int, elapsedSeconds: Double) {
        self.root = root
        self.totalAllocatedBytes = totalAllocatedBytes
        self.totalFileCount = totalFileCount
        self.explainedBytes = explainedBytes
        self.entries = entries
        self.skippedProtectedCount = skippedProtectedCount
        self.elapsedSeconds = elapsedSeconds
    }

    /// The coverage gap: bytes no recipe explains.
    public var unexplainedBytes: Int64 { totalAllocatedBytes - explainedBytes }
}

/// Whole-volume attribution sweep: one enumeration pass over a root,
/// accumulating allocated size into directories up to `depth` levels deep.
/// Read-only, like everything in the scanner. This is the "causal map"
/// foundation — it shows where the bytes are, recipe-covered or not.
public struct VolumeSweep: Sendable {
    public let root: String
    public let depth: Int
    public let minBytes: Int64
    public let recipes: [Recipe]

    public init(root: String = NSHomeDirectory(), depth: Int = 3,
                minBytes: Int64 = 500 * 1024 * 1024, recipes: [Recipe] = RecipeCatalog.all) {
        self.root = root
        self.depth = depth
        self.minBytes = minBytes
        self.recipes = recipes
    }

    /// Bundle extensions treated as atomic: report the bundle, never its guts.
    /// Deleting inside these (e.g. .photoslibrary) can corrupt the bundle.
    static let atomicBundleSuffixes = [
        ".photoslibrary", ".musiclibrary", ".tvlibrary", ".imovielibrary",
        ".fcpbundle", ".app", ".framework", ".migratedphotolibrary", ".aplibrary",
    ]

    public func run(progress: (@Sendable (Int) -> Void)? = nil) -> SweepReport {
        let start = Date()
        let rootURL = URL(fileURLWithPath: root)
        let rootComponents = rootURL.pathComponents.count

        var sizes: [String: Int64] = [:]
        var counts: [String: Int] = [:]
        var totalBytes: Int64 = 0
        var explainedBytes: Int64 = 0
        var totalFiles = 0

        final class SkipCounter { var count = 0 }
        let skips = SkipCounter()

        // Resolve recipe paths once, up front, for per-file attribution.
        let recipePaths: [(id: String, path: String)] = recipes.flatMap { recipe in
            recipe.paths.flatMap { raw in
                PathResolver.resolve(raw).map { (recipe.id, $0) }
            }
        }

        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in skips.count += 1; return true }
        )

        while let item = enumerator?.nextObject() as? URL {
            guard let values = try? item.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            let bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            totalBytes += bytes
            totalFiles += 1
            if totalFiles % 100_000 == 0 { progress?(totalFiles) }

            let path = item.path
            // Coverage: does any recipe path contain this file? Counted once
            // per file, so the explained/unexplained split has no double counting.
            if recipePaths.contains(where: { path.hasPrefix($0.path + "/") || path == $0.path }) {
                explainedBytes += bytes
            }

            // Credit the file's size to each ancestor directory within depth,
            // stopping at atomic bundles so their internals are never listed.
            let components = item.pathComponents
            let maxLevel = min(components.count - 1, rootComponents + depth)
            guard maxLevel >= rootComponents + 1 else { continue }
            for level in (rootComponents + 1)...maxLevel {
                let name = components[level - 1]
                let dir = components[0..<level].joined(separator: "/").replacingOccurrences(of: "//", with: "/")
                sizes[dir, default: 0] += bytes
                counts[dir, default: 0] += 1
                // Don't descend past a bundle boundary.
                if Self.atomicBundleSuffixes.contains(where: { name.hasSuffix($0) }) { break }
            }
        }

        /// A directory is explained only if it sits AT or BELOW a recipe path.
        /// A recipe buried deep inside ~/Library does not explain ~/Library.
        func explain(_ dir: String) -> String? {
            recipePaths.first { dir == $0.path || dir.hasPrefix($0.path + "/") }?.id
        }

        let entries = sizes
            .filter { $0.value >= minBytes }
            .map { SweepEntry(path: $0.key, allocatedBytes: $0.value,
                              fileCount: counts[$0.key] ?? 0, explainedBy: explain($0.key)) }
            .sorted { $0.allocatedBytes > $1.allocatedBytes }

        return SweepReport(
            root: root,
            totalAllocatedBytes: totalBytes,
            totalFileCount: totalFiles,
            explainedBytes: explainedBytes,
            entries: entries,
            skippedProtectedCount: skips.count,
            elapsedSeconds: Date().timeIntervalSince(start)
        )
    }
}
