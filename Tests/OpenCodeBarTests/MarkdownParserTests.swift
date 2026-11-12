import XCTest
@testable import OpenCodeBar

final class MarkdownParserTests: XCTestCase {
    func testPlainParagraph() {
        let blocks = MarkdownParser.parse("Just some text.")
        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let text) = blocks[0] else {
            return XCTFail("expected paragraph")
        }
        XCTAssertEqual(text, "Just some text.")
        XCTAssertFalse(MarkdownParser.hasRichBlocks("Just some text."))
    }

    func testHeading() {
        let blocks = MarkdownParser.parse("## A heading\n\nBody")
        XCTAssertEqual(blocks.count, 2)
        guard case .heading(let level, let text) = blocks[0] else {
            return XCTFail("expected heading")
        }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(text, "A heading")
    }

    func testFencedCode() {
        let blocks = MarkdownParser.parse("```swift\nlet x = 1\nprint(x)\n```")
        XCTAssertEqual(blocks.count, 1)
        guard case .code(let language, let code) = blocks[0] else {
            return XCTFail("expected code")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let x = 1\nprint(x)")
    }

    func testUnorderedList() {
        let blocks = MarkdownParser.parse("- one\n- two\n- three")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let ordered, let items) = blocks[0] else {
            return XCTFail("expected list")
        }
        XCTAssertFalse(ordered)
        XCTAssertEqual(items.map(\.text), ["one", "two", "three"])
    }

    func testOrderedList() {
        let blocks = MarkdownParser.parse("1. first\n2. second")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let ordered, let items) = blocks[0] else {
            return XCTFail("expected list")
        }
        XCTAssertTrue(ordered)
        XCTAssertEqual(items.map(\.text), ["first", "second"])
    }

    func testTable() {
        let markdown = """
        | Name | Value |
        | :--- | ---: |
        | foo  | 1     |
        | bar  | 2     |
        """
        let blocks = MarkdownParser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let table) = blocks[0] else {
            return XCTFail("expected table")
        }
        XCTAssertEqual(table.headers, ["Name", "Value"])
        XCTAssertEqual(table.alignments, [.leading, .trailing])
        XCTAssertEqual(table.rows, [["foo", "1"], ["bar", "2"]])
        XCTAssertTrue(MarkdownParser.hasRichBlocks(markdown))
    }

    func testBlockquote() {
        let blocks = MarkdownParser.parse("> quoted text\n> more")
        XCTAssertEqual(blocks.count, 1)
        guard case .quote(let inner) = blocks[0] else {
            return XCTFail("expected quote")
        }
        XCTAssertEqual(inner.count, 1)
        guard case .paragraph(let text) = inner[0] else {
            return XCTFail("expected paragraph inside quote")
        }
        XCTAssertEqual(text, "quoted text\nmore")
    }

    func testRule() {
        let blocks = MarkdownParser.parse("Before\n\n---\n\nAfter")
        XCTAssertEqual(blocks.count, 3)
        guard case .rule = blocks[1] else {
            return XCTFail("expected rule")
        }
    }

    func testMixedBlocksPreserveParagraphs() {
        let markdown = "Intro paragraph.\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n- item"
        let blocks = MarkdownParser.parse(markdown)
        XCTAssertEqual(blocks.count, 3)
        guard case .paragraph = blocks[0] else { return XCTFail("expected paragraph first") }
        guard case .table = blocks[1] else { return XCTFail("expected table second") }
        guard case .list = blocks[2] else { return XCTFail("expected list third") }
    }
}
