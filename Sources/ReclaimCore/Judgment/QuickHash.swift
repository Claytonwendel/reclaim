import Foundation
import CryptoKit

/// Fast content fingerprint for duplicate detection. Files are only hashed
/// after they already match on exact byte size, so a sampled hash (head +
/// tail for large files, full hash for small) makes false collisions
/// vanishingly unlikely while keeping the scan fast. Read-only.
enum QuickHash {
    static let fullHashLimit: Int64 = 4 * 1024 * 1024   // hash small files whole
    static let sampleSize = 1024 * 1024                  // 1 MB head + 1 MB tail

    static func hash(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        var hasher = SHA256()

        if size <= fullHashLimit {
            guard let data = try? handle.readToEnd() else { return nil }
            hasher.update(data: data)
        } else {
            // Head.
            if let head = try? handle.read(upToCount: sampleSize) {
                hasher.update(data: head)
            }
            // Tail.
            try? handle.seek(toOffset: UInt64(max(0, size - Int64(sampleSize))))
            if let tail = try? handle.readToEnd() {
                hasher.update(data: tail)
            }
            // Mix in the size so different-length files never collide.
            withUnsafeBytes(of: size) { hasher.update(data: Data($0)) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
