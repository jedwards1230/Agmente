import XCTest
import ACP
@testable import ACPClient

final class ToolCallContentParsingTests: XCTestCase {

    // MARK: - Parser

    func testParsesDiffBlockWithOldText() {
        let update: [String: ACP.Value] = [
            "content": .array([
                .object([
                    "type": .string("diff"),
                    "path": .string("/abs/path/File.swift"),
                    "oldText": .string("before"),
                    "newText": .string("after"),
                ])
            ])
        ]

        let blocks = ACPSessionUpdateParser.toolCallContent(from: update)

        XCTAssertEqual(blocks, [
            .diff(ACPToolCallDiff(path: "/abs/path/File.swift", oldText: "before", newText: "after"))
        ])
        XCTAssertEqual(blocks.diffs.count, 1)
        XCTAssertFalse(blocks.diffs[0].isCreation)
    }

    func testParsesDiffBlockWithoutOldTextIsCreation() {
        let update: [String: ACP.Value] = [
            "content": .array([
                .object([
                    "type": .string("diff"),
                    "path": .string("/abs/path/New.swift"),
                    "newText": .string("brand new"),
                ])
            ])
        ]

        let blocks = ACPSessionUpdateParser.toolCallContent(from: update)

        XCTAssertEqual(blocks, [
            .diff(ACPToolCallDiff(path: "/abs/path/New.swift", oldText: nil, newText: "brand new"))
        ])
        XCTAssertTrue(blocks.diffs[0].isCreation)
        XCTAssertNil(blocks.diffs[0].oldText)
    }

    func testParsesMixedTextAndDiffBlocks() {
        let update: [String: ACP.Value] = [
            "content": .array([
                .object([
                    "type": .string("content"),
                    "content": .object([
                        "type": .string("text"),
                        "text": .string("On branch main"),
                    ]),
                ]),
                .object([
                    "type": .string("diff"),
                    "path": .string("/p"),
                    "oldText": .string("a"),
                    "newText": .string("b"),
                ]),
            ])
        ]

        let blocks = ACPSessionUpdateParser.toolCallContent(from: update)

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0], .text("On branch main"))
        XCTAssertEqual(blocks[1], .diff(ACPToolCallDiff(path: "/p", oldText: "a", newText: "b")))
        XCTAssertEqual(blocks.diffs, [ACPToolCallDiff(path: "/p", oldText: "a", newText: "b")])
    }

    func testSkipsMalformedDiffMissingNewText() {
        let update: [String: ACP.Value] = [
            "content": .array([
                .object([
                    "type": .string("diff"),
                    "path": .string("/p"),
                ])
            ])
        ]

        XCTAssertTrue(ACPSessionUpdateParser.toolCallContent(from: update).isEmpty)
    }

    func testReturnsEmptyWhenNoContentArray() {
        XCTAssertTrue(ACPSessionUpdateParser.toolCallContent(from: [:]).isEmpty)
    }

    // MARK: - Handler wiring

    func testToolCallUpdateCarriesDiffContent() {
        let handler = ACPSessionUpdateHandler()
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("tool_call_update"),
                "toolCallId": .string("tc-diff"),
                "status": .string("completed"),
                "kind": .string("edit"),
                "content": .array([
                    .object([
                        "type": .string("diff"),
                        "path": .string("/abs/Main.swift"),
                        "oldText": .string("let x = 1"),
                        "newText": .string("let x = 2"),
                    ])
                ]),
            ]),
        ])

        let events = handler.handle(params: params)

        XCTAssertEqual(events.count, 1)
        guard case .toolCallUpdate(let update) = events[0] else {
            return XCTFail("Expected toolCallUpdate event")
        }
        XCTAssertEqual(update.diffs, [
            ACPToolCallDiff(path: "/abs/Main.swift", oldText: "let x = 1", newText: "let x = 2")
        ])
    }

    func testToolCallCarriesCreationDiffContent() {
        let handler = ACPSessionUpdateHandler()
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("tool_call"),
                "toolCallId": .string("tc-create"),
                "title": .string("Create file"),
                "kind": .string("edit"),
                "status": .string("in_progress"),
                "content": .array([
                    .object([
                        "type": .string("diff"),
                        "path": .string("/abs/New.swift"),
                        "newText": .string("created"),
                    ])
                ]),
            ]),
        ])

        let events = handler.handle(params: params)

        XCTAssertEqual(events.count, 1)
        guard case .toolCall(let info) = events[0] else {
            return XCTFail("Expected toolCall event")
        }
        XCTAssertEqual(info.diffs.count, 1)
        XCTAssertTrue(info.diffs[0].isCreation)
        XCTAssertEqual(info.diffs[0].newText, "created")
    }
}
