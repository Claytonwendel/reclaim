import Foundation

/// Detects whether Reclaim has been granted Full Disk Access (FDA).
///
/// Why it matters: without FDA, macOS silently hides TCC-protected data
/// (Messages, Mail, Safari, many app containers) from file enumeration. That
/// makes the "My Mac" map under-count — real usage lands in the unitemized
/// remainder — and hides removable caches from cleanup. So FDA is what makes
/// both storage *showing* and storage *saving* actually accurate.
///
/// The probe is a plain read attempt against known TCC-gated paths. Making the
/// attempt is also what registers Reclaim in the Full Disk Access list, so the
/// user only has to flip a switch instead of adding the app by hand.
///
/// Pure Foundation (no AppKit) so it stays usable from the CLI too.
public enum FullDiskAccess: Sendable {
    public enum Status: String, Sendable, Codable {
        case granted        // a protected resource read successfully
        case denied         // a protected resource exists but is blocked
        case undetermined   // nothing conclusive on this Mac (rare)
    }

    /// TCC-gated locations. The system TCC database is the gold-standard probe
    /// (present on every Mac, readable only with FDA); the rest are
    /// storage-relevant and cover Macs where the first is somehow unreadable
    /// for other reasons.
    static func probePaths() -> [String] {
        let home = NSHomeDirectory()
        return [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Mail",
            home + "/Library/Messages",
            home + "/Library/Safari",
        ]
    }

    /// Current access status. Attempting these reads also registers Reclaim in
    /// System Settings → Privacy & Security → Full Disk Access.
    public static func status() -> Status {
        let fm = FileManager.default
        var sawExisting = false
        for path in probePaths() where fm.fileExists(atPath: path) {
            sawExisting = true
            if isReadable(path) { return .granted }
        }
        // Some protected paths exist but none could be read → access is off.
        // Nothing at all present → can't say (don't nag).
        return sawExisting ? .denied : .undetermined
    }

    public static var isGranted: Bool { status() == .granted }

    /// Actually read the resource — `fileExists` alone doesn't prove access,
    /// since macOS reports protected paths as existing even when reads are
    /// blocked. A directory is probed by listing it; a file by reading a byte.
    private static func isReadable(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            return false
        }
        if isDir.boolValue {
            return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
        }
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        // Reading a byte forces the TCC check; open alone can succeed lazily.
        return (try? handle.read(upToCount: 1)) != nil
    }
}
