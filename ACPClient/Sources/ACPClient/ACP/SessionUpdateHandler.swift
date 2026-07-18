import Foundation
import ACP

// MARK: - Session Update Events

/// High-level events emitted when interpreting session/update notifications.
public enum ACPSessionUpdateEvent: Equatable, Sendable {
    /// Agent is streaming thought/reasoning content.
    case agentThought(text: String)
    
    /// User message chunk (typically echo of submitted prompt during replay).
    case userMessage(text: String)
    
    /// Agent is streaming response text.
    case agentMessage(text: String)
    
    /// A tool call has been initiated.
    case toolCall(ACPToolCallInfo)
    
    /// An existing tool call has been updated (status change, output, etc.).
    case toolCallUpdate(ACPToolCallUpdate)
    
    /// The agent's current mode has changed.
    case modeChange(modeId: String)

    /// Session config options changed.
    case configOptionsUpdate(options: [ACPSessionConfigOption])
    
    /// Available slash commands have been updated.
    case availableCommandsUpdate(commands: [SessionCommand])

    /// Context-window usage and cost for the session have been updated.
    case usageUpdate(ACPUsageInfo)

    /// Session metadata (title / last-activity timestamp) has been updated.
    case sessionInfoUpdate(ACPSessionInfo)

    /// The agent's plan changed. This is a full snapshot that replaces any
    /// prior plan for the session; an empty array means the plan was cleared.
    case plan(entries: [ACPPlanEntry])
}

// MARK: - Session Info Model

/// Session metadata carried by a `session_info_update` notification.
///
/// All fields are optional (the notification supports partial updates). A field
/// that is present but null in the payload is an explicit *clear*, which is
/// distinct from an absent field — use the `has…` flags to tell them apart so a
/// consumer never wipes a value the update did not mention.
///
/// Note: this notification does not carry `cwd`. The working directory lives on
/// the `SessionInfo` returned by `session/list`, not here.
public struct ACPSessionInfo: Equatable, Sendable {
    /// New human-readable title. `nil` means the field was absent or explicitly
    /// cleared — disambiguate with ``hasTitle``.
    public let title: String?

    /// Whether the update included a `title` field (present, possibly null).
    public let hasTitle: Bool

    /// ISO 8601 timestamp of last activity, as sent. `nil` means the field was
    /// absent or explicitly cleared — disambiguate with ``hasUpdatedAt``.
    public let updatedAt: String?

    /// Whether the update included an `updatedAt` field (present, possibly null).
    public let hasUpdatedAt: Bool

    public init(title: String?, hasTitle: Bool, updatedAt: String?, hasUpdatedAt: Bool) {
        self.title = title
        self.hasTitle = hasTitle
        self.updatedAt = updatedAt
        self.hasUpdatedAt = hasUpdatedAt
    }

    /// ``updatedAt`` parsed as a `Date`, when it is a valid ISO 8601 timestamp.
    /// Accepts timestamps with or without fractional seconds.
    public var updatedAtDate: Date? {
        guard let updatedAt else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: updatedAt) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: updatedAt)
    }
}

// MARK: - Tool Call Models

/// Information about a tool call from a session update.
public struct ACPToolCallInfo: Equatable, Sendable {
    public let toolCallId: String?
    public let title: String
    public let kind: String?
    public let status: String
    /// Typed content blocks attached to the tool call (e.g. structured diffs).
    public let content: [ACPToolCallContent]

    public init(
        toolCallId: String?,
        title: String,
        kind: String?,
        status: String,
        content: [ACPToolCallContent] = []
    ) {
        self.toolCallId = toolCallId
        self.title = title
        self.kind = kind
        self.status = status
        self.content = content
    }

    /// The structured file diffs attached to this tool call, in order.
    public var diffs: [ACPToolCallDiff] { content.diffs }
}

/// Update to an existing tool call.
public struct ACPToolCallUpdate: Equatable, Sendable {
    public let toolCallId: String?
    public let status: String?
    public let title: String?
    public let kind: String?
    public let output: String?
    /// Typed content blocks attached to the update (e.g. structured diffs).
    public let content: [ACPToolCallContent]

    public init(
        toolCallId: String?,
        status: String?,
        title: String?,
        kind: String?,
        output: String?,
        content: [ACPToolCallContent] = []
    ) {
        self.toolCallId = toolCallId
        self.status = status
        self.title = title
        self.kind = kind
        self.output = output
        self.content = content
    }

    /// The structured file diffs attached to this update, in order.
    public var diffs: [ACPToolCallDiff] { content.diffs }
}

// MARK: - Usage Models

/// Context-window usage and cumulative cost from a `usage_update` session update.
///
/// Mirrors the ACP `UsageUpdate` schema: `used` and `size` are token counts and
/// are always present; `cost` is reported only by agents that track it.
public struct ACPUsageInfo: Equatable, Sendable {
    /// Tokens currently in the context window.
    public let used: Int
    /// Total context window size, in tokens.
    public let size: Int
    /// Cumulative session cost, if the agent reports it.
    public let cost: ACPUsageCost?

    public init(used: Int, size: Int, cost: ACPUsageCost? = nil) {
        self.used = used
        self.size = size
        self.cost = cost
    }

    /// Fraction of the context window in use (0...1), or nil if `size` is 0.
    public var fraction: Double? {
        guard size > 0 else { return nil }
        return Double(used) / Double(size)
    }
}

/// Cumulative session cost reported by a `usage_update` (ACP `Cost` schema).
public struct ACPUsageCost: Equatable, Sendable {
    /// Total cumulative cost for the session.
    public let amount: Double
    /// ISO 4217 currency code (e.g. "USD").
    public let currency: String

    public init(amount: Double, currency: String) {
        self.amount = amount
        self.currency = currency
    }
}

// MARK: - Session Update Handler

/// Interprets raw session/update notification payloads and emits typed events.
///
/// Usage:
/// ```swift
/// let handler = ACPSessionUpdateHandler()
/// let events = handler.handle(params: notification.params)
/// for event in events {
///     switch event {
///     case .agentMessage(let text): // append to chat
///     case .toolCall(let info): // show tool call UI
///     // ...
///     }
/// }
/// ```
public final class ACPSessionUpdateHandler: Sendable {
    public init() {}
    
    /// Interprets a session/update notification and returns typed events.
    /// - Parameters:
    ///   - params: The `params` field from the session/update notification.
    ///   - activeSessionId: If provided, events for other sessions are filtered out.
    /// - Returns: Array of typed events. May be empty if the update is not relevant.
    public func handle(params: ACP.Value?, activeSessionId: String? = nil) -> [ACPSessionUpdateEvent] {
        let parsed = ACPSessionUpdateParser.parse(params: params)
        
        // Filter by session if specified
        if let activeSessionId, let sessionId = parsed.sessionId, sessionId != activeSessionId {
            return []
        }
        
        guard let kind = parsed.kind else {
            // Unknown update type - try to extract text as fallback
            let text = ACPSessionUpdateParser.extractText(from: parsed.update)
            if !text.isEmpty {
                return [.agentMessage(text: text)]
            }
            return []
        }
        
        return interpretUpdate(kind: kind, update: parsed.update)
    }
    
    /// Interprets a parsed update by kind.
    private func interpretUpdate(kind: String, update: [String: ACP.Value]) -> [ACPSessionUpdateEvent] {
        switch kind {
        case "agent_thought_chunk":
            let text = ACPSessionUpdateParser.extractText(from: update)
            guard !text.isEmpty else { return [] }
            return [.agentThought(text: text)]
            
        case "user_message_chunk":
            let text = ACPSessionUpdateParser.userMessageText(from: update)
            guard !text.isEmpty else { return [] }
            return [.userMessage(text: text)]
            
        case "agent_message_chunk":
            let text = ACPSessionUpdateParser.extractText(from: update)
            guard !text.isEmpty else { return [] }
            return [.agentMessage(text: text)]
            
        case "tool_call":
            let info = parseToolCallInfo(from: update)
            return [.toolCall(info)]
            
        case "tool_call_update":
            let updateInfo = parseToolCallUpdate(from: update)
            return [.toolCallUpdate(updateInfo)]
            
        case "current_mode_update":
            if let modeId = update["modeId"]?.stringValue {
                return [.modeChange(modeId: modeId)]
            }
            return []

        case "config_option_update":
            let options = ACPSessionConfigOptionParser.parse(from: update)
            guard !options.isEmpty else { return [] }
            return [.configOptionsUpdate(options: options)]
            
        case "available_commands_update":
            let commands = parseAvailableCommands(from: update)
            return [.availableCommandsUpdate(commands: commands)]

        case "usage_update":
            guard let info = parseUsageInfo(from: update) else { return [] }
            return [.usageUpdate(info)]

        case "session_info_update":
            guard let info = parseSessionInfo(from: update) else { return [] }
            return [.sessionInfoUpdate(info)]

        case "plan":
            // The plan is a full snapshot; always emit (even when empty) so the
            // consumer can replace or clear the current plan.
            let entries = ACPSessionUpdateParser.planEntries(from: update)
            return [.plan(entries: entries)]

        default:
            // Unknown kind - try to extract text as fallback
            let text = ACPSessionUpdateParser.extractText(from: update)
            if !text.isEmpty {
                return [.agentMessage(text: text)]
            }
            return []
        }
    }
    
    // MARK: - Parsing Helpers
    
    private func parseToolCallInfo(from update: [String: ACP.Value]) -> ACPToolCallInfo {
        let title = ACPSessionUpdateParser.toolCallTitle(from: update)
        let kind = ACPSessionUpdateParser.toolCallKind(from: update)
        let toolCallId = ACPSessionUpdateParser.toolCallId(from: update)
        let status = ACPSessionUpdateParser.toolCallStatus(from: update) ?? "pending"
        let content = ACPSessionUpdateParser.toolCallContent(from: update)

        return ACPToolCallInfo(
            toolCallId: toolCallId,
            title: title,
            kind: kind,
            status: status,
            content: content
        )
    }
    
    private func parseToolCallUpdate(from update: [String: ACP.Value]) -> ACPToolCallUpdate {
        let toolCallId = ACPSessionUpdateParser.toolCallId(from: update)
        let status = ACPSessionUpdateParser.toolCallStatus(from: update)
        let title = ACPSessionUpdateParser.toolCallUpdatedTitle(from: update)
        let kind = ACPSessionUpdateParser.toolCallUpdatedKind(from: update)
        let output = ACPSessionUpdateParser.toolCallOutput(from: update)
        let content = ACPSessionUpdateParser.toolCallContent(from: update)

        return ACPToolCallUpdate(
            toolCallId: toolCallId,
            status: status,
            title: title,
            kind: kind,
            output: output,
            content: content
        )
    }
    
    private func parseUsageInfo(from update: [String: ACP.Value]) -> ACPUsageInfo? {
        // `used` and `size` are required by the ACP schema; drop the update if either is absent.
        guard let used = update["used"]?.intValue,
              let size = update["size"]?.intValue else {
            return nil
        }

        var cost: ACPUsageCost?
        if let costObject = update["cost"]?.objectValue,
           let amount = costObject["amount"]?.doubleValue,
           let currency = costObject["currency"]?.stringValue {
            cost = ACPUsageCost(amount: amount, currency: currency)
        }

        return ACPUsageInfo(used: used, size: size, cost: cost)
    }

    private func parseSessionInfo(from update: [String: ACP.Value]) -> ACPSessionInfo? {
        // A key present in the payload — even as JSON null — signals intent to
        // set/clear that field. An absent key must leave the value untouched.
        let hasTitle = update["title"] != nil
        let hasUpdatedAt = update["updatedAt"] != nil

        // Nothing actionable if the update mentions neither metadata field.
        guard hasTitle || hasUpdatedAt else { return nil }

        return ACPSessionInfo(
            title: update["title"]?.stringValue,
            hasTitle: hasTitle,
            updatedAt: update["updatedAt"]?.stringValue,
            hasUpdatedAt: hasUpdatedAt
        )
    }

    private func parseAvailableCommands(from update: [String: ACP.Value]) -> [SessionCommand] {
        guard case let .array(commandValues)? = update["availableCommands"] else { return [] }
        
        return commandValues.compactMap { value in
            guard let commandObj = value.objectValue,
                  let name = commandObj["name"]?.stringValue,
                  let description = commandObj["description"]?.stringValue else { return nil }
            let inputHint = commandObj["input"]?.objectValue?["hint"]?.stringValue
            
            return SessionCommand(id: name, name: name, description: description, inputHint: inputHint)
        }
    }
}

// MARK: - Convenience Extensions

public extension ACPSessionUpdateHandler {
    /// Extract the session ID from a session/update notification.
    static func sessionId(from params: ACP.Value?) -> String? {
        ACPSessionUpdateParser.parse(params: params).sessionId
    }
}
