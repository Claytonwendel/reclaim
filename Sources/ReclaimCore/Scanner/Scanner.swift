import Foundation

/// Read-only scanner. Principle: a scan never mutates the computer.
/// It resolves recipe paths, measures allocated + apparent size, checks
/// process state, and honors macOS protections as hard stops.
public struct StorageScanner: Sendable {

    public var recipes: [Recipe]

    public init(recipes: [Recipe] = RecipeCatalog.all) {
        self.recipes = recipes
    }

    public func scan(progress: (@Sendable (String) -> Void)? = nil) -> ScanReport {
        let start = Date()
        let running = RunningProcessProbe.snapshot()
        var findings: [Finding] = []

        for recipe in recipes {
            progress?(recipe.displayName)
            for rawPath in recipe.paths {
                for resolved in PathResolver.resolve(rawPath) {
                    let measurement = SizeMeasurement.measure(resolved)
                    guard measurement.allocatedBytes >= recipe.thresholdBytes else { continue }
                    let blocking = recipe.requiresQuit.contains { running.contains($0.lowercased()) }
                    findings.append(Finding(
                        recipeID: recipe.id,
                        displayName: recipe.displayName,
                        group: recipe.group,
                        path: resolved,
                        allocatedBytes: measurement.allocatedBytes,
                        apparentBytes: measurement.apparentBytes,
                        riskTier: recipe.riskTier,
                        action: recipe.action,
                        explanation: recipe.explanation,
                        impact: recipe.impact,
                        recurrence: recipe.recurrence,
                        lastModified: measurement.lastModified,
                        blockingAppRunning: blocking,
                        skippedProtectedPaths: measurement.skippedProtected
                    ))
                }
            }
        }

        findings.sort { $0.allocatedBytes > $1.allocatedBytes }

        let volume = VolumeProbe.dataVolume()
        return ScanReport(
            scannedAt: start,
            hostname: ProcessInfo.processInfo.hostName,
            volumeTotalBytes: volume.total,
            volumeFreeBytes: volume.free,
            findings: findings,
            elapsedSeconds: Date().timeIntervalSince(start)
        )
    }
}

// MARK: - Path resolution (~ and single-level glob)

enum PathResolver {
    /// Expands `~` and resolves glob patterns. Deep-glob (`**`) is limited to
    /// a bounded search under home to keep scans fast.
    static func resolve(_ raw: String) -> [String] {
        let expanded = NSString(string: raw).expandingTildeInPath
        guard expanded.contains("*") else {
            return FileManager.default.fileExists(atPath: expanded) ? [expanded] : []
        }
        // `**` deep patterns are deferred to the repo-aware module (Phase 3);
        // skip them in v0 rather than walk the whole disk.
        guard !expanded.contains("**") else { return [] }

        let dir = (expanded as NSString).deletingLastPathComponent
        let pattern = (expanded as NSString).lastPathComponent
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return entries
            .filter { fnmatch(pattern, $0, 0) == 0 }
            .map { (dir as NSString).appendingPathComponent($0) }
    }
}

// MARK: - Size measurement

struct Measurement {
    var allocatedBytes: Int64 = 0
    var apparentBytes: Int64 = 0
    var lastModified: Date?
    var skippedProtected: [String] = []
}

enum SizeMeasurement {
    private static let keys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .totalFileSizeKey, .fileSizeKey,
        .isRegularFileKey, .contentModificationDateKey,
    ]

    static func measure(_ path: String) -> Measurement {
        var result = Measurement()
        let url = URL(fileURLWithPath: path)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return result }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
            result.lastModified = attrs[.modificationDate] as? Date
        }

        if !isDir.boolValue {
            if let values = try? url.resourceValues(forKeys: keys) {
                result.allocatedBytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                result.apparentBytes = Int64(values.totalFileSize ?? values.fileSize ?? 0)
            }
            return result
        }

        // Directory: enumerate. errorHandler records protected paths and
        // continues — "Operation not permitted" is reported, never bypassed.
        final class SkipBox { var paths: [String] = [] }
        let skips = SkipBox()
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { failedURL, _ in
                skips.paths.append(failedURL.path)
                return true // keep scanning the rest
            }
        )
        while let item = enumerator?.nextObject() as? URL {
            guard let values = try? item.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            result.allocatedBytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            result.apparentBytes += Int64(values.totalFileSize ?? values.fileSize ?? 0)
        }
        result.skippedProtected = skips.paths
        return result
    }
}

// MARK: - Process + volume probes

enum RunningProcessProbe {
    /// Lowercased names of running processes, via `ps` (works without AppKit,
    /// so the CLI stays usable over SSH; the app can layer NSWorkspace later).
    static func snapshot() -> Set<String> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axco", "comm"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").dropFirst().map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        })
    }
}

enum VolumeProbe {
    static func dataVolume() -> (total: Int64, free: Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]) else { return (0, 0) }
        return (
            Int64(values.volumeTotalCapacity ?? 0),
            values.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }
}
