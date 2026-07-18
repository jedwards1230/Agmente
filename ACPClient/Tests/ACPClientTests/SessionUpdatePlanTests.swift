import XCTest
import ACP
@testable import ACPClient

/// Coverage for decoding the ACP `plan` session update (a full-snapshot
/// checklist of plan entries).
final class SessionUpdatePlanTests: XCTestCase {
    private let handler = ACPSessionUpdateHandler()

    private func planParams(entries: [ACP.Value], sessionId: String = "session-1") -> ACP.Value {
        .object([
            "sessionId": .string(sessionId),
            "update": .object([
                "sessionUpdate": .string("plan"),
                "entries": .array(entries),
            ]),
        ])
    }

    // MARK: - Enum fallbacks

    func testPriorityWireMapping() {
        XCTAssertEqual(ACPPlanEntryPriority(wire: "high"), .high)
        XCTAssertEqual(ACPPlanEntryPriority(wire: "MEDIUM"), .medium)
        XCTAssertEqual(ACPPlanEntryPriority(wire: "low"), .low)
        XCTAssertEqual(ACPPlanEntryPriority(wire: "critical"), .unknown)
        XCTAssertEqual(ACPPlanEntryPriority(wire: nil), .unknown)
    }

    func testStatusWireMapping() {
        XCTAssertEqual(ACPPlanEntryStatus(wire: "pending"), .pending)
        XCTAssertEqual(ACPPlanEntryStatus(wire: "in_progress"), .inProgress)
        XCTAssertEqual(ACPPlanEntryStatus(wire: "completed"), .completed)
        XCTAssertEqual(ACPPlanEntryStatus(wire: "blocked"), .unknown)
        XCTAssertEqual(ACPPlanEntryStatus(wire: nil), .unknown)
    }

    // MARK: - Handler decode

    func testPlanUpdateMixedStatusesAndPriorities() {
        let params = planParams(entries: [
            .object([
                "content": .string("Investigate the bug"),
                "priority": .string("high"),
                "status": .string("completed"),
            ]),
            .object([
                "content": .string("Write the fix"),
                "priority": .string("medium"),
                "status": .string("in_progress"),
            ]),
            .object([
                "content": .string("Add tests"),
                "priority": .string("low"),
                "status": .string("pending"),
            ]),
        ])

        let events = handler.handle(params: params)

        XCTAssertEqual(events.count, 1)
        guard case .plan(let entries) = events[0] else {
            return XCTFail("Expected plan event")
        }
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0], ACPPlanEntry(id: 0, content: "Investigate the bug", priority: .high, status: .completed))
        XCTAssertEqual(entries[1], ACPPlanEntry(id: 1, content: "Write the fix", priority: .medium, status: .inProgress))
        XCTAssertEqual(entries[2], ACPPlanEntry(id: 2, content: "Add tests", priority: .low, status: .pending))
    }

    func testPlanUpdateUnknownEnumValuesDecodeGracefully() {
        let params = planParams(entries: [
            .object([
                "content": .string("Do the thing"),
                "priority": .string("urgent"),
                "status": .string("paused"),
            ]),
        ])

        let events = handler.handle(params: params)

        guard case .plan(let entries) = events.first else {
            return XCTFail("Expected plan event")
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].priority, .unknown)
        XCTAssertEqual(entries[0].status, .unknown)
        XCTAssertEqual(entries[0].content, "Do the thing")
    }

    func testPlanUpdateMissingPriorityAndStatusDefaultToUnknown() {
        let params = planParams(entries: [
            .object(["content": .string("Bare entry")]),
        ])

        let events = handler.handle(params: params)

        guard case .plan(let entries) = events.first else {
            return XCTFail("Expected plan event")
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0], ACPPlanEntry(id: 0, content: "Bare entry", priority: .unknown, status: .unknown))
    }

    func testPlanUpdateSkipsMalformedEntries() {
        let params = planParams(entries: [
            .string("not-an-object"),
            .object(["priority": .string("high")]), // no content
            .object(["content": .string("   ")]),   // blank content
            .object(["content": .string("Keep me"), "status": .string("pending")]),
        ])

        let events = handler.handle(params: params)

        guard case .plan(let entries) = events.first else {
            return XCTFail("Expected plan event")
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].content, "Keep me")
    }

    func testEmptyPlanEntriesEmitsClearedSnapshot() {
        let params = planParams(entries: [])

        let events = handler.handle(params: params)

        XCTAssertEqual(events.count, 1)
        guard case .plan(let entries) = events[0] else {
            return XCTFail("Expected plan event")
        }
        XCTAssertTrue(entries.isEmpty)
    }

    func testPlanUpdateFiltersByActiveSession() {
        let params = planParams(entries: [
            .object(["content": .string("Ignored")]),
        ], sessionId: "other-session")

        let events = handler.handle(params: params, activeSessionId: "session-1")

        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Summary

    func testSummarizePlanReportsCount() {
        let params = planParams(entries: [
            .object(["content": .string("One")]),
            .object(["content": .string("Two")]),
        ])

        XCTAssertEqual(
            ACPSessionUpdateParser.summarize(params: params),
            "session/update [session-1] plan: 2 item(s)"
        )
    }

    func testSummarizePlanReportsCleared() {
        let params = planParams(entries: [])

        XCTAssertEqual(
            ACPSessionUpdateParser.summarize(params: params),
            "session/update [session-1] plan cleared"
        )
    }
}
