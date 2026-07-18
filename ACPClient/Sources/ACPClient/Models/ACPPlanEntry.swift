import Foundation

/// Relative priority of a plan entry, per the ACP `plan` session update.
///
/// The wire protocol defines `high`/`medium`/`low`; any value we don't
/// recognize decodes to `.unknown` rather than failing the whole update.
public enum ACPPlanEntryPriority: String, Sendable, Equatable, CaseIterable {
    case high
    case medium
    case low
    case unknown

    /// Maps a raw wire string to a priority, defaulting unrecognized values to
    /// `.unknown` so a future/mistyped priority never crashes decoding.
    public init(wire: String?) {
        switch wire?.lowercased() {
        case "high": self = .high
        case "medium": self = .medium
        case "low": self = .low
        default: self = .unknown
        }
    }
}

/// Execution status of a plan entry, per the ACP `plan` session update.
///
/// The wire protocol defines `pending`/`in_progress`/`completed`; any value we
/// don't recognize decodes to `.unknown` rather than failing the whole update.
public enum ACPPlanEntryStatus: String, Sendable, Equatable, CaseIterable {
    case pending
    case inProgress = "in_progress"
    case completed
    case unknown

    /// Maps a raw wire string to a status, defaulting unrecognized values to
    /// `.unknown` so a future/mistyped status never crashes decoding.
    public init(wire: String?) {
        switch wire?.lowercased() {
        case "pending": self = .pending
        case "in_progress": self = .inProgress
        case "completed": self = .completed
        default: self = .unknown
        }
    }
}

/// A single entry in an agent's plan, decoded from a `plan` session update.
///
/// The agent sends its full current plan as a snapshot on every `plan` update,
/// so a fresh update replaces the prior plan for the session.
public struct ACPPlanEntry: Sendable, Equatable, Identifiable {
    public let id: Int
    public let content: String
    public let priority: ACPPlanEntryPriority
    public let status: ACPPlanEntryStatus

    public init(
        id: Int = 0,
        content: String,
        priority: ACPPlanEntryPriority,
        status: ACPPlanEntryStatus
    ) {
        self.id = id
        self.content = content
        self.priority = priority
        self.status = status
    }
}
