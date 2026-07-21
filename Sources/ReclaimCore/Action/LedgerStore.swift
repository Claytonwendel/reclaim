import Foundation

/// Append-only history of cleanup sessions at ~/.reclaim/ledger.json.
/// This is the durable record behind "prove the outcome" and the growth
/// story ("Reclaim has recovered X GB across N sessions").
public struct LedgerStore: Sendable {
    public let path: String

    public init(home: String = NSHomeDirectory()) {
        self.path = (home as NSString).appendingPathComponent(".reclaim/ledger.json")
    }

    public func all() -> [CleanupLedgerEntry] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CleanupLedgerEntry].self, from: data)) ?? []
    }

    public func append(_ entry: CleanupLedgerEntry) throws {
        var entries = all()
        entries.append(entry)
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entries).write(to: URL(fileURLWithPath: path))
    }

    /// Lifetime bytes moved to quarantine across all sessions.
    public var lifetimeQuarantinedBytes: Int64 {
        all().reduce(0) { $0 + $1.quarantinedBytes }
    }
}
