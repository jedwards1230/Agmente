import Foundation
import Testing
import ACPClient
@testable import Agmente

struct ToolCallDiffLinesTests {

    @Test func creationMarksEveryLineAdded() {
        let lines = ToolCallDiffLines.compute(old: nil, new: "line one\nline two")

        #expect(lines.map(\.kind) == [.added, .added])
        #expect(lines.map(\.text) == ["line one", "line two"])
    }

    @Test func singleLineEditShowsRemovedThenAdded() {
        let lines = ToolCallDiffLines.compute(old: "let x = 1", new: "let x = 2")

        #expect(lines.count == 2)
        #expect(lines[0].kind == .removed)
        #expect(lines[0].text == "let x = 1")
        #expect(lines[1].kind == .added)
        #expect(lines[1].text == "let x = 2")
    }

    @Test func keepsSurroundingContextForMiddleEdit() {
        let old = "a\nb\nOLD\nd\ne"
        let new = "a\nb\nNEW\nd\ne"

        let lines = ToolCallDiffLines.compute(old: old, new: new)

        // context (a, b) + removed OLD + added NEW + context (d, e)
        #expect(lines.map(\.kind) == [.unchanged, .unchanged, .removed, .added, .unchanged, .unchanged])
        #expect(lines.first?.text == "a")
        #expect(lines.last?.text == "e")
    }

    @Test func collapsesLongUnchangedRunsIntoGaps() {
        let old = (1...10).map { "line \($0)" }.joined(separator: "\n") + "\nOLD"
        let new = (1...10).map { "line \($0)" }.joined(separator: "\n") + "\nNEW"

        let lines = ToolCallDiffLines.compute(old: old, new: new)

        #expect(lines.first?.kind == .gap)
        // Only `contextLines` unchanged lines are kept before the change.
        let unchanged = lines.filter { $0.kind == .unchanged }
        #expect(unchanged.count == ToolCallDiffLines.contextLines)
        #expect(lines.contains { $0.kind == .removed && $0.text == "OLD" })
        #expect(lines.contains { $0.kind == .added && $0.text == "NEW" })
    }

    @Test func viewComputesAddedAndRemovedFromDiff() {
        let diff = ACPToolCallDiff(path: "/tmp/File.swift", oldText: "old", newText: "new")
        let lines = ToolCallDiffLines.compute(old: diff.oldText, new: diff.newText)

        #expect(lines.filter { $0.kind == .added }.count == 1)
        #expect(lines.filter { $0.kind == .removed }.count == 1)
    }
}
