import XCTest
@testable import OpenCodeBar

final class ModelCatalogTests: XCTestCase {
    private func model(
        _ id: String,
        provider: String,
        name: String? = nil,
        variants: [String] = []
    ) -> ModelInfo {
        ModelInfo(
            id: id,
            modelID: id,
            providerID: provider,
            name: name,
            enabled: true,
            status: "active",
            variants: variants.map { ModelInfo.Variant(id: $0, name: $0.capitalized) }
        )
    }

    private var catalog: [ModelInfo] {
        [
            model("zeta", provider: "opencode-go", name: "Zeta"),
            model("alpha", provider: "opencode-go", name: "Alpha"),
            model("gpt-5", provider: "openai", name: "GPT-5", variants: ["high", "low"]),
            model("claude", provider: "anthropic", name: "Claude"),
        ]
    }

    func testProviderIDsAreUniqueAndSorted() {
        let providers = (catalog + [model("alpha", provider: "opencode-go", name: "Alpha")]).providerIDs
        XCTAssertEqual(providers, ["anthropic", "openai", "opencode-go"])
    }

    func testBlankQueryKeepsEveryModel() {
        XCTAssertEqual(
            catalog.filteringModels(query: "   ", providerID: nil).count,
            catalog.count
        )
    }

    func testQueryMatchesNameIDAndProvider() {
        XCTAssertEqual(
            catalog.filteringModels(query: "gpt", providerID: nil).map(\.id),
            ["gpt-5"]
        )
        XCTAssertEqual(
            catalog.filteringModels(query: "CLAUDE", providerID: nil).map(\.id),
            ["claude"]
        )
        XCTAssertEqual(
            catalog.filteringModels(query: "opencode", providerID: nil).map(\.id).sorted(),
            ["alpha", "zeta"]
        )
    }

    func testProviderFilterCombinesWithQuery() {
        XCTAssertEqual(
            catalog.filteringModels(query: "", providerID: "opencode-go").map(\.id).sorted(),
            ["alpha", "zeta"]
        )
        XCTAssertTrue(
            catalog.filteringModels(query: "claude", providerID: "opencode-go").isEmpty
        )
    }

    func testGroupsAreSortedAndDropEmptyProviders() {
        let groups = catalog.groupedByProvider()
        XCTAssertEqual(groups.map(\.providerID), ["anthropic", "openai", "opencode-go"])
        XCTAssertEqual(groups.last?.models.map(\.displayName), ["Alpha", "Zeta"])
        XCTAssertTrue(
            catalog.filteringModels(query: "gpt", providerID: nil).groupedByProvider()
                .map(\.providerID) == ["openai"]
        )
    }

    func testFlatSortIgnoresProvider() {
        XCTAssertEqual(
            catalog.sortedByDisplayName().map(\.displayName),
            ["Alpha", "Claude", "GPT-5", "Zeta"]
        )
    }
}
