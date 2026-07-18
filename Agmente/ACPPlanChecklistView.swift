import SwiftUI
import ACPClient

/// Pure mapping from plan entry status/priority to presentation values.
///
/// Kept free of SwiftUI view state so it can be unit-tested directly.
enum ACPPlanRowStyle {
    /// SF Symbol name representing a plan entry's status.
    static func symbolName(for status: ACPPlanEntryStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .completed: return "checkmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Tint for a plan entry's status indicator.
    static func symbolColor(for status: ACPPlanEntryStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .inProgress: return .blue
        case .completed: return .green
        case .unknown: return .secondary
        }
    }

    /// Accent tint for a plan entry's priority.
    static func priorityColor(for priority: ACPPlanEntryPriority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .secondary
        case .unknown: return .secondary
        }
    }

    /// Short label for a plan entry's priority, or `nil` when there's nothing
    /// meaningful to show (unknown priority).
    static func priorityLabel(for priority: ACPPlanEntryPriority) -> String? {
        switch priority {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .unknown: return nil
        }
    }

    static func isCompleted(_ status: ACPPlanEntryStatus) -> Bool {
        status == .completed
    }

    /// Number of completed entries in a plan snapshot.
    static func completedCount(_ entries: [ACPPlanEntry]) -> Int {
        entries.filter { $0.status == .completed }.count
    }
}

/// A live checklist rendering of the agent's current plan (an ACP `plan`
/// session update snapshot). Each row shows the entry's status and content,
/// tinted by priority.
struct ACPPlanChecklistView: View {
    let entries: [ACPPlanEntry]

    private var completedCount: Int { ACPPlanRowStyle.completedCount(entries) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(entries) { entry in
                row(for: entry)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .accessibilityIdentifier("acp-plan-checklist")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.clipboard")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Plan")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(completedCount)/\(entries.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func row(for entry: ACPPlanEntry) -> some View {
        let completed = ACPPlanRowStyle.isCompleted(entry.status)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: ACPPlanRowStyle.symbolName(for: entry.status))
                .font(.system(size: 15))
                .foregroundStyle(ACPPlanRowStyle.symbolColor(for: entry.status))
                .accessibilityHidden(true)

            Text(entry.content)
                .font(.subheadline)
                .foregroundStyle(completed ? .secondary : .primary)
                .strikethrough(completed, color: .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let priorityLabel = ACPPlanRowStyle.priorityLabel(for: entry.priority) {
                Text(priorityLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ACPPlanRowStyle.priorityColor(for: entry.priority))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(ACPPlanRowStyle.priorityColor(for: entry.priority).opacity(0.12))
                    )
            }
        }
        .accessibilityElement(children: .combine)
    }
}
