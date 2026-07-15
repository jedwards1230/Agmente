import XCTest
import ACP
@testable import ACPClient

final class SessionUpdateHandlerTests: XCTestCase {
    let handler = ACPSessionUpdateHandler()
    
    // MARK: - Agent Message Tests
    
    func testAgentMessageChunk() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("agent_message_chunk"),
                "content": .string("Hello, world!")
            ])
        ])
        
        let events = handler.handle(params: params)
        
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .agentMessage(text: "Hello, world!"))
    }
    
    func testAgentMessageChunkWithNestedContent() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("agent_message_chunk"),
                "content": .object([
                    "text": .string("Nested text content")
                ])
            ])
        ])
        
        let events = handler.handle(params: params)
        
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .agentMessage(text: "Nested text content"))
    }
    
    // MARK: - Agent Thought Tests
    
    func testAgentThoughtChunk() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("agent_thought_chunk"),
                "content": .string("I'm thinking about...")
            ])
        ])
        
        let events = handler.handle(params: params)
        
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .agentThought(text: "I'm thinking about..."))
    }
    
    // MARK: - User Message Tests
    
    func testUserMessageChunk() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("user_message_chunk"),
                "content": .string("User says hello")
            ])
        ])
        
        let events = handler.handle(params: params)
        
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .userMessage(text: "User says hello"))
    }
    
    // MARK: - Tool Call Tests
    
    func testToolCall() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("tool_call"),
                "toolCallId": .string("tc-123"),
                "title": .string("Read file"),
                "kind": .string("read"),
                "status": .string("in_progress")
            ])
        ])
        
        let events = handler.handle(params: params)
        
        XCTAssertEqual(events.count, 1)
        guard case .toolCall(let info) = events[0] else {
            XCTFail("Expected toolCall event")
            return
        }
        XCTAssertEqual(info.toolCallId, "tc-123")
        XCTAssertEqual(info.title, "Read file")
        XCTAssertEqual(info.kind, "read")
        XCTAssertEqual(info.status, "in_progress")
    }
    
    func testToolCallWithMinimalFields() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("tool_call"),
                "title": .string("Some tool")
            ])
        ])
        
        let events = handler.handle(params: params)
        
        XCTAssertEqual(events.count, 1)
        guard case .toolCall(let info) = events[0] else {
            XCTFail("Expected toolCall event")
            return
        }
        XCTAssertNil(info.toolCallId)
        XCTAssertEqual(info.title, "Some tool")
        XCTAssertNil(info.kind)
        XCTAssertEqual(info.status, "pending")
    }
    
    // MARK: - Tool Call Update Tests
    
    func testToolCallUpdate() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("tool_call_update"),
                "toolCallId": .string("tc-123"),
                "status": .string("completed"),
                "rawOutput": .string("File contents here")
            ])
        ])
        
        let events = handler.handle(params: params)
        
        XCTAssertEqual(events.count, 1)
        guard case .toolCallUpdate(let update) = events[0] else {
            XCTFail("Expected toolCallUpdate event")
            return
        }
        XCTAssertEqual(update.toolCallId, "tc-123")
        XCTAssertEqual(update.status, "completed")
        XCTAssertEqual(update.output, "File contents here")
    }
    
    func testToolCallUpdateWithTitleAndKind() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("tool_call_update"),
                "toolCallId": .string("tc-456"),
                "title": .string("Updated title"),
                "kind": .string("edit"),
                "status": .string("in_progress")
            ])
        ])
        
        let events = handler.handle(params: params)
        
        XCTAssertEqual(events.count, 1)
        guard case .toolCallUpdate(let update) = events[0] else {
            XCTFail("Expected toolCallUpdate event")
            return
        }
        XCTAssertEqual(update.toolCallId, "tc-456")
        XCTAssertEqual(update.title, "Updated title")
        XCTAssertEqual(update.kind, "edit")
        XCTAssertEqual(update.status, "in_progress")
    }

    func testToolCallUpdateUsesContentArrayOutput() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("tool_call_update"),
                "toolCallId": .string("tc-789"),
                "status": .string("completed"),
                "content": .array([
                    .object([
                        "type": .string("content"),
                        "content": .object([
                            "type": .string("text"),
                            "text": .string("On branch main")
                        ])
                    ])
                ])
            ])
        ])

        let events = handler.handle(params: params)

        XCTAssertEqual(events.count, 1)
        guard case .toolCallUpdate(let update) = events[0] else {
            XCTFail("Expected toolCallUpdate event")
            return
        }
        XCTAssertEqual(update.toolCallId, "tc-789")
        XCTAssertEqual(update.status, "completed")
        XCTAssertEqual(update.output, "On branch main")
    }
    
    // MARK: - Mode Change Tests
    
    func testModeChange() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("current_mode_update"),
                "modeId": .string("plan")
            ])
        ])
        
        let events = handler.handle(params: params)
        
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .modeChange(modeId: "plan"))
    }
    
    func testModeChangeMissingModeId() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("current_mode_update")
            ])
        ])
        
        let events = handler.handle(params: params)
        
        XCTAssertEqual(events.count, 0)
    }
    
    // MARK: - Available Commands Tests
    
    func testAvailableCommandsUpdate() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("available_commands_update"),
                "availableCommands": .array([
                    .object([
                        "name": .string("compact"),
                        "description": .string("Toggle compact mode"),
                        "input": .object([
                            "hint": .string("on|off")
                        ])
                    ]),
                    .object([
                        "name": .string("clear"),
                        "description": .string("Clear the conversation")
                    ])
                ])
            ])
        ])
        
        let events = handler.handle(params: params)
        
        XCTAssertEqual(events.count, 1)
        guard case .availableCommandsUpdate(let commands) = events[0] else {
            XCTFail("Expected availableCommandsUpdate event")
            return
        }
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[0].name, "compact")
        XCTAssertEqual(commands[0].description, "Toggle compact mode")
        XCTAssertEqual(commands[0].inputHint, "on|off")
        XCTAssertEqual(commands[1].name, "clear")
        XCTAssertEqual(commands[1].description, "Clear the conversation")
        XCTAssertNil(commands[1].inputHint)
    }
    
    // MARK: - Usage Update Tests

    func testUsageUpdateWithCost() throws {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "sessionUpdate": .string("usage_update"),
                "used": .int(12000),
                "size": .int(200000),
                "cost": .object([
                    "amount": .double(0.0342),
                    "currency": .string("USD")
                ])
            ])
        ])

        let events = handler.handle(params: params)

        XCTAssertEqual(events.count, 1)
        guard case .usageUpdate(let info) = events[0] else {
            XCTFail("Expected usageUpdate event")
            return
        }
        XCTAssertEqual(info.used, 12000)
        XCTAssertEqual(info.size, 200000)
        XCTAssertEqual(info.cost?.amount, 0.0342)
        XCTAssertEqual(info.cost?.currency, "USD")
        let fraction = try XCTUnwrap(info.fraction)
        XCTAssertEqual(fraction, 0.06, accuracy: 0.0001)
    }

    func testUsageUpdateWithoutCost() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "sessionUpdate": .string("usage_update"),
                "used": .int(50),
                "size": .int(100)
            ])
        ])

        let events = handler.handle(params: params)

        XCTAssertEqual(events.count, 1)
        guard case .usageUpdate(let info) = events[0] else {
            XCTFail("Expected usageUpdate event")
            return
        }
        XCTAssertEqual(info.used, 50)
        XCTAssertEqual(info.size, 100)
        XCTAssertNil(info.cost)
        XCTAssertEqual(info.fraction, 0.5)
    }

    func testUsageUpdateMissingRequiredFieldIsDropped() {
        // `size` is required by the ACP schema; without it the update is ignored.
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "sessionUpdate": .string("usage_update"),
                "used": .int(12000)
            ])
        ])

        let events = handler.handle(params: params)

        XCTAssertEqual(events.count, 0)
    }

    func testUsageUpdateIgnoresMalformedCost() {
        // A partial `cost` object (missing currency) leaves cost nil but keeps the token counts.
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "sessionUpdate": .string("usage_update"),
                "used": .int(10),
                "size": .int(100),
                "cost": .object([
                    "amount": .double(1.5)
                ])
            ])
        ])

        let events = handler.handle(params: params)

        XCTAssertEqual(events.count, 1)
        guard case .usageUpdate(let info) = events[0] else {
            XCTFail("Expected usageUpdate event")
            return
        }
        XCTAssertEqual(info.used, 10)
        XCTAssertNil(info.cost)
    }

    // MARK: - Session Info Update Tests

    func testSessionInfoUpdateTitleAndTimestamp() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "sessionUpdate": .string("session_info_update"),
                "title": .string("Refactor auth flow"),
                "updatedAt": .string("2026-07-15T17:46:00Z")
            ])
        ])

        let events = handler.handle(params: params)

        XCTAssertEqual(events.count, 1)
        guard case .sessionInfoUpdate(let info) = events[0] else {
            XCTFail("Expected sessionInfoUpdate event")
            return
        }
        XCTAssertEqual(info.title, "Refactor auth flow")
        XCTAssertTrue(info.hasTitle)
        XCTAssertEqual(info.updatedAt, "2026-07-15T17:46:00Z")
        XCTAssertTrue(info.hasUpdatedAt)
        XCTAssertNotNil(info.updatedAtDate)
    }

    func testSessionInfoUpdateTitleOnlyLeavesTimestampUntouched() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "sessionUpdate": .string("session_info_update"),
                "title": .string("Just a title")
            ])
        ])

        let events = handler.handle(params: params)

        XCTAssertEqual(events.count, 1)
        guard case .sessionInfoUpdate(let info) = events[0] else {
            XCTFail("Expected sessionInfoUpdate event")
            return
        }
        XCTAssertEqual(info.title, "Just a title")
        XCTAssertTrue(info.hasTitle)
        XCTAssertNil(info.updatedAt)
        XCTAssertFalse(info.hasUpdatedAt)
    }

    func testSessionInfoUpdateNullTitleSignalsClear() {
        // A present-but-null field is an explicit clear, distinct from absent.
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "sessionUpdate": .string("session_info_update"),
                "title": .null
            ])
        ])

        let events = handler.handle(params: params)

        XCTAssertEqual(events.count, 1)
        guard case .sessionInfoUpdate(let info) = events[0] else {
            XCTFail("Expected sessionInfoUpdate event")
            return
        }
        XCTAssertNil(info.title)
        XCTAssertTrue(info.hasTitle, "A present null title should still be flagged as provided")
        XCTAssertFalse(info.hasUpdatedAt)
    }

    func testSessionInfoUpdateWithoutFieldsIsDropped() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "sessionUpdate": .string("session_info_update")
            ])
        ])

        let events = handler.handle(params: params)

        XCTAssertEqual(events.count, 0)
    }

    // MARK: - Session Filtering Tests
    
    func testFiltersByActiveSession() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-other"),
            "update": .object([
                "type": .string("agent_message_chunk"),
                "content": .string("Should be ignored")
            ])
        ])
        
        let events = handler.handle(params: params, activeSessionId: "session-1")
        
        XCTAssertEqual(events.count, 0)
    }
    
    func testAcceptsMatchingSession() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("agent_message_chunk"),
                "content": .string("Should be included")
            ])
        ])
        
        let events = handler.handle(params: params, activeSessionId: "session-1")
        
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .agentMessage(text: "Should be included"))
    }
    
    func testNoFilteringWithoutActiveSession() {
        let params: ACP.Value = .object([
            "sessionId": .string("any-session"),
            "update": .object([
                "type": .string("agent_message_chunk"),
                "content": .string("Included")
            ])
        ])
        
        let events = handler.handle(params: params, activeSessionId: nil)
        
        XCTAssertEqual(events.count, 1)
    }
    
    // MARK: - Unknown Update Type Tests
    
    func testUnknownTypeWithText() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("unknown_type"),
                "content": .string("Some text")
            ])
        ])
        
        let events = handler.handle(params: params)
        
        // Falls back to agent message for unknown types with text
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .agentMessage(text: "Some text"))
    }
    
    func testUnknownTypeWithoutText() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("unknown_type"),
                "metadata": .object(["key": .string("value")])
            ])
        ])
        
        let events = handler.handle(params: params)
        
        XCTAssertEqual(events.count, 0)
    }
    
    // MARK: - Edge Cases
    
    func testNilParams() {
        let events = handler.handle(params: nil)
        XCTAssertEqual(events.count, 0)
    }
    
    func testEmptyUpdate() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([:])
        ])
        
        let events = handler.handle(params: params)
        
        XCTAssertEqual(events.count, 0)
    }
    
    func testEmptyTextContent() {
        let params: ACP.Value = .object([
            "sessionId": .string("session-1"),
            "update": .object([
                "type": .string("agent_message_chunk"),
                "content": .string("")
            ])
        ])
        
        let events = handler.handle(params: params)
        
        XCTAssertEqual(events.count, 0)
    }
    
    // MARK: - Session ID Extraction
    
    func testSessionIdExtraction() {
        let params: ACP.Value = .object([
            "sessionId": .string("extracted-session-id"),
            "update": .object([:])
        ])
        
        let sessionId = ACPSessionUpdateHandler.sessionId(from: params)
        
        XCTAssertEqual(sessionId, "extracted-session-id")
    }
    
    func testSessionIdExtractionNil() {
        let params: ACP.Value = .object([
            "update": .object([:])
        ])
        
        let sessionId = ACPSessionUpdateHandler.sessionId(from: params)
        
        XCTAssertNil(sessionId)
    }
}