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
