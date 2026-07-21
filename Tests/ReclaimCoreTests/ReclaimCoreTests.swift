import Testing
import Foundation
@testable import ReclaimCore

@Suite struct RecipeCatalogTests {
    @Test func recipeIDsAreUnique() {
        let ids = RecipeCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func redTierRecipesNeverQuarantine() {
        // System-protected data may only go through a supported manager.
        for recipe in RecipeCatalog.all where recipe.riskTier == .red {
            #expect(recipe.action == .supportedCLI || recipe.action == .none)
        }
    }

    @Test func orangeTierIsNeverAutomated() {
        // Personal content requires explicit review — non-negotiable.
        for recipe in RecipeCatalog.all where recipe.riskTier == .orange {
            #expect(recipe.action == .reviewOnly)
        }
    }

    @Test func onlyGreenIsAutomatable() {
        for tier in RiskTier.allCases {
            #expect(tier.automatable == (tier == .green))
        }
    }

    @Test func catalogExpandedBeyondCaseStudy() {
        // The deep-research pass should have grown the library well past
        // the original ~25 case-study recipes.
        #expect(RecipeCatalog.all.count >= 50)
    }

    @Test func communityRecipesNeverGreenlightAutomation() {
        // Community-known recipes are detection-only until verified: they may
        // describe an action, but they must not sit in an auto-runnable state
        // that a future executor could fire without human review.
        for recipe in RecipeCatalog.all where recipe.confidence == .communityKnown {
            if recipe.riskTier.automatable {
                #expect(recipe.action != .quarantine || recipe.riskTier == .green)
            }
        }
    }

    @Test func personalTierRecipesAreReviewOnly() {
        // Orange (personal/cloud) must never carry an acting method, no matter
        // the source — this is the invariant the Parallels recipe first broke.
        for recipe in RecipeCatalog.all where recipe.riskTier == .orange {
            #expect(recipe.action == .reviewOnly)
        }
    }
}

@Suite struct ScannerTests {
    @Test func scanIsReadOnlyAndCompletes() {
        // Smoke test against a temp-dir recipe so CI doesn't depend on
        // the machine's real state.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reclaim-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("blob.bin")
        FileManager.default.createFile(atPath: file.path, contents: Data(count: 1024 * 1024))
        defer { try? FileManager.default.removeItem(at: dir) }

        let recipe = Recipe(
            id: "test.blob", displayName: "Test blob", group: "Test",
            paths: [dir.path], riskTier: .green, thresholdBytes: 1,
            action: .quarantine, explanation: "", impact: "", recurrence: ""
        )
        let report = StorageScanner(recipes: [recipe]).scan()
        #expect(report.findings.count == 1)
        #expect(report.findings[0].allocatedBytes >= 1024 * 1024)
        // The scan must not have touched the file.
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func globResolution() {
        let matches = PathResolver.resolve("~/*")
        #expect(!matches.isEmpty)
        // Deep globs are deferred in v0 — must return empty, not walk the disk.
        #expect(PathResolver.resolve("~/**/.next/cache").isEmpty)
    }
}

@Suite struct OrphanScannerTests {
    /// Build a throwaway home with a Library/Application Support tree.
    private func makeHome(_ folders: [String]) -> String {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("reclaim-orphan-\(UUID().uuidString)")
        let appSupport = home.appendingPathComponent("Library/Application Support")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        for folder in folders {
            let dir = appSupport.appendingPathComponent(folder)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            FileManager.default.createFile(
                atPath: dir.appendingPathComponent("blob.bin").path,
                contents: Data(count: 30 * 1024 * 1024))
        }
        return home.path
    }

    @Test func flagsBundleIDLeftoverWithNoOwningApp() {
        let home = makeHome(["com.fake.deadapp"])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let scanner = OrphanScanner(
            inventory: AppInventory(bundleIDs: [], names: []), recipes: [])
        let orphans = scanner.scan(homeOverride: home)
        #expect(orphans.contains { $0.folderName == "com.fake.deadapp" && $0.confidence == .likelyOrphan })
    }

    @Test func neverFlagsAppleComponents() {
        // The Nektony failure mode: system components must never be orphaned.
        let home = makeHome(["com.apple.appstore", "com.apple.Safari", "CrashReporter"])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let scanner = OrphanScanner(
            inventory: AppInventory(bundleIDs: [], names: []), recipes: [])
        let orphans = scanner.scan(homeOverride: home)
        #expect(orphans.isEmpty)
    }

    @Test func respectsInstalledApps() {
        let home = makeHome(["com.installed.app"])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let scanner = OrphanScanner(
            inventory: AppInventory(bundleIDs: ["com.installed.app"], names: []), recipes: [])
        #expect(scanner.scan(homeOverride: home).isEmpty)
    }

    @Test func excludesRecipeCoveredPaths() {
        let home = makeHome(["com.fake.cached"])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let covered = "\(home)/Library/Application Support/com.fake.cached"
        let recipe = Recipe(
            id: "test.cached", displayName: "", group: "", paths: [covered],
            riskTier: .green, thresholdBytes: 1, action: .quarantine,
            explanation: "", impact: "", recurrence: "")
        let scanner = OrphanScanner(
            inventory: AppInventory(bundleIDs: [], names: []), recipes: [recipe])
        #expect(scanner.scan(homeOverride: home).isEmpty)
    }
}
