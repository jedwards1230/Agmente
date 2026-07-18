import Foundation
import ACP

public enum ACPSessionUpdateParser {
    public static func parse(params: ACP.Value?) -> (sessionId: String?, update: [String: ACP.Value], kind: String?) {
        guard let object = params?.objectValue else { return (nil, [:], nil) }
        let session = object["sessionId"]?.stringValue
        let update = object["update"]?.objectValue ?? object["sessionUpdate"]?.objectValue ?? [:]
        let kind = update["sessionUpdate"]?.stringValue ?? update["type"]?.stringValue
        return (session, update, kind)
    }

    public static func summarize(
        params: ACP.Value?,
        fallbackCompact: (([String: ACP.Value]) -> String)? = nil
    ) -> String {
        guard let object = params?.objectValue else { return "session/update" }
        let session = object["sessionId"]?.stringValue ?? "unknown"
        let update = object["update"]?.objectValue ?? object["sessionUpdate"]?.objectValue ?? [:]
        let kind = update["sessionUpdate"]?.stringValue ?? update["type"]?.stringValue

        if let kind {
            switch kind {
            case "plan":
                let entries = planEntries(from: update)
                if entries.isEmpty {
                    return "session/update [\(session)] plan cleared"
                }
                return "session/update [\(session)] plan: \(entries.count) item(s)"
            case "agent_message_chunk":
                let text = extractText(from: update)
                return "session/update [\(session)] message: \(text)"
            case "tool_call":
                let title = update["title"]?.stringValue ?? update["name"]?.stringValue ?? "tool"
                let toolKind = update["kind"]?.stringValue
                if let toolKind = toolKind {
                    return "session/update [\(session)] tool_call [\(toolKind)] \(title)"
                }
                return "session/update [\(session)] tool_call \(title)"
            case "tool_call_update":
                let status = update["status"]?.stringValue ?? "unknown"
                return "session/update [\(session)] tool_call_update: \(status)"
            case "available_commands_update":
                return "session/update [\(session)] available commands updated"
            case "current_mode_update":
                if let mode = update["modeId"]?.stringValue {
                    return "session/update [\(session)] mode -> \(mode)"
                }
            case "config_option_update":
                let options = ACPSessionConfigOptionParser.parse(from: update)
                return "session/update [\(session)] config options updated (\(options.count))"
            case "usage_update":
                let used = update["used"]?.intValue ?? 0
                let size = update["size"]?.intValue ?? 0
                return "session/update [\(session)] usage: \(used)/\(size) tokens"
            case "session_info_update":
                let title = update["title"]?.stringValue
                return "session/update [\(session)] info: \(title ?? "(untitled)")"
            default:
                break
            }
        }

        let compact = fallbackCompact?(update) ?? compactJSON(update)
        return "session/update [\(session)] \(compact)"
    }

    /// Decode the entries of a `plan` session update into typed plan entries.
    ///
    /// The agent sends its full current plan each time (a snapshot), so callers
    /// should treat the result as a replacement for any prior plan. An empty or
    /// missing `entries` array yields an empty result (a cleared plan). Entries
    /// missing a `content` string are skipped; unknown priority/status values
    /// decode gracefully to `.unknown` rather than failing the update.
    public static func planEntries(from update: [String: ACP.Value]) -> [ACPPlanEntry] {
        guard let entries = update["entries"]?.arrayValue else { return [] }
        var result: [ACPPlanEntry] = []
        result.reserveCapacity(entries.count)
        for value in entries {
            guard let object = value.objectValue else { continue }
            guard let content = object["content"]?.stringValue,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let entry = ACPPlanEntry(
                id: result.count,
                content: content,
                priority: ACPPlanEntryPriority(wire: object["priority"]?.stringValue),
                status: ACPPlanEntryStatus(wire: object["status"]?.stringValue)
            )
            result.append(entry)
        }
        return result
    }

    /// Extract human-readable text from a session/update payload.
    public static func extractText(from update: [String: ACP.Value]) -> String {
        if let text = update["content"]?.stringValue {
            return text
        }
        if let text = update["content"]?.objectValue?["text"]?.stringValue {
            return text
        }
        if case let .array(items)? = update["content"] {
            for element in items {
                if let text = element.objectValue?["content"]?.objectValue?["text"]?.stringValue {
                    return text
                }
                if let text = element.objectValue?["text"]?.stringValue {
                    return text
                }
            }
        }
        return ""
    }

    public static func userMessageText(from update: [String: ACP.Value]) -> String {
        extractText(from: update)
    }

    public static func toolCallTitle(from update: [String: ACP.Value], fallback: String = "Unknown tool") -> String {
        let title = update["title"]?.stringValue
            ?? update["name"]?.stringValue
            ?? update["toolName"]?.stringValue
        return title?.isEmpty == false ? title! : fallback
    }

    public static func toolCallId(from update: [String: ACP.Value]) -> String? {
        update["toolCallId"]?.stringValue
    }

    public static func toolCallKind(from update: [String: ACP.Value]) -> String? {
        update["kind"]?.stringValue
    }

    public static func toolCallStatus(from update: [String: ACP.Value]) -> String? {
        update["status"]?.stringValue
    }

    public static func toolCallUpdatedTitle(from update: [String: ACP.Value]) -> String? {
        let title = update["title"]?.stringValue
            ?? update["name"]?.stringValue
            ?? update["toolName"]?.stringValue
        return title?.isEmpty == true ? nil : title
    }

    public static func toolCallUpdatedKind(from update: [String: ACP.Value]) -> String? {
        let kind = update["kind"]?.stringValue
        return kind?.isEmpty == true ? nil : kind
    }

    public static func toolCallOutput(from update: [String: ACP.Value]) -> String? {
        let text = update["rawOutput"]?.stringValue ?? extractText(from: update)
        return text.isEmpty ? nil : text
    }

    /// Decode the typed content blocks from a tool call's `content` array.
    ///
    /// Recognizes the `diff` variant (`{ type: "diff", path, oldText?, newText }`)
    /// and text blocks (`{ type: "content", content: { text } }`). Unknown block
    /// types are skipped. `oldText` absent maps to a file creation.
    public static func toolCallContent(from update: [String: ACP.Value]) -> [ACPToolCallContent] {
        guard case let .array(items)? = update["content"] else { return [] }

        var blocks: [ACPToolCallContent] = []
        blocks.reserveCapacity(items.count)

        for element in items {
            guard let object = element.objectValue else { continue }

            switch object["type"]?.stringValue {
            case "diff":
                guard let path = object["path"]?.stringValue,
                      let newText = object["newText"]?.stringValue else { continue }
                let oldText = object["oldText"]?.stringValue
                blocks.append(.diff(ACPToolCallDiff(path: path, oldText: oldText, newText: newText)))
            default:
                // "content" (wrapped text) blocks, or any legacy/flat text shape.
                if let text = object["content"]?.objectValue?["text"]?.stringValue {
                    blocks.append(.text(text))
                } else if let text = object["text"]?.stringValue {
                    blocks.append(.text(text))
                }
            }
        }

        return blocks
    }

    private static func compactJSON(_ object: [String: ACP.Value]) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(ACP.Value.object(object)),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
