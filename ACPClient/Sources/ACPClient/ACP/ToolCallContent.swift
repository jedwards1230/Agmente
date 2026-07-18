import Foundation
import ACP

// MARK: - Tool Call Content Blocks

/// A structured file diff carried by a tool-call content block (`type: "diff"`).
///
/// Mirrors the ACP `ToolCallContent` diff variant emitted on `tool_call` /
/// `tool_call_update` session updates:
///
/// ```json
/// { "type": "diff", "path": "/abs/path", "oldText": "before", "newText": "after" }
/// ```
///
/// `oldText` is omitted when the edit creates a new file.
public struct ACPToolCallDiff: Equatable, Sendable, Codable {
    /// Absolute path of the file being changed.
    public let path: String
    /// The prior file contents, or `nil` when the file is being created.
    public let oldText: String?
    /// The file contents after the edit.
    public let newText: String

    public init(path: String, oldText: String?, newText: String) {
        self.path = path
        self.oldText = oldText
        self.newText = newText
    }

    /// `true` when there is no prior text — i.e. the edit creates a new file.
    public var isCreation: Bool { oldText == nil }
}

/// A single content block attached to a tool call.
///
/// ACP models several `ToolCallContent` variants; Agmente decodes the two the
/// daemon currently produces:
/// - `.text` — a wrapped text block
///   (`{ "type": "content", "content": { "text": "..." } }`)
/// - `.diff` — a structured file diff (`{ "type": "diff", ... }`)
///
/// The `image`, `audio`, `resource`, and `resource_link` variants are modeled
/// in the ACP spec but intentionally not decoded yet — no producer emits them
/// server-side. Add cases here (and a renderer) when a producer lands.
public enum ACPToolCallContent: Equatable, Sendable {
    case text(String)
    case diff(ACPToolCallDiff)
}

public extension Sequence where Element == ACPToolCallContent {
    /// The structured file diffs among these content blocks, in order.
    var diffs: [ACPToolCallDiff] {
        compactMap { block in
            if case .diff(let diff) = block { return diff }
            return nil
        }
    }
}
