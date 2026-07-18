import SwiftUI
import ACPClient

/// A single rendered line of a structured tool-call diff.
struct DiffLine: Identifiable, Equatable {
    enum Kind: Equatable {
        case unchanged
        case added
        case removed
        /// A collapsed run of unchanged context lines.
        case gap
    }

    let id: Int
    let kind: Kind
    let text: String
}

/// Pure line-diffing used by ``ToolCallDiffView``.
///
/// Produces a compact before/after view by comparing the common prefix and
/// suffix of the two texts and treating the differing middle as removed-then-added
/// lines. Unchanged context beyond ``contextLines`` on each side is collapsed into
/// a `.gap` marker so large files still render a small diff.
enum ToolCallDiffLines {
    static let contextLines = 3

    static func compute(old: String?, new: String) -> [DiffLine] {
        let newLines = new.components(separatedBy: "\n")

        // Creation: no prior text, everything is added.
        guard let old else {
            return newLines.enumerated().map { DiffLine(id: $0.offset, kind: .added, text: $0.element) }
        }

        let oldLines = old.components(separatedBy: "\n")

        // Common leading lines.
        var prefix = 0
        while prefix < oldLines.count, prefix < newLines.count, oldLines[prefix] == newLines[prefix] {
            prefix += 1
        }

        // Common trailing lines (not overlapping the prefix).
        var suffix = 0
        while suffix < (oldLines.count - prefix),
              suffix < (newLines.count - prefix),
              oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix] {
            suffix += 1
        }

        let removed = Array(oldLines[prefix..<(oldLines.count - suffix)])
        let added = Array(newLines[prefix..<(newLines.count - suffix)])

        var lines: [DiffLine] = []
        var id = 0
        func append(_ kind: DiffLine.Kind, _ text: String) {
            lines.append(DiffLine(id: id, kind: kind, text: text))
            id += 1
        }

        // Leading context (last `contextLines` of the common prefix).
        let leadContext = Array(oldLines[0..<prefix])
        if leadContext.count > contextLines {
            append(.gap, "")
        }
        for line in leadContext.suffix(contextLines) {
            append(.unchanged, line)
        }

        for line in removed { append(.removed, line) }
        for line in added { append(.added, line) }

        // Trailing context (first `contextLines` of the common suffix).
        let tailContext = Array(oldLines[(oldLines.count - suffix)..<oldLines.count])
        for line in tailContext.prefix(contextLines) {
            append(.unchanged, line)
        }
        if tailContext.count > contextLines {
            append(.gap, "")
        }

        return lines
    }
}

/// Renders a single structured file diff (`ACPToolCallDiff`) as a compact
/// added/removed line view with red/green accents.
struct ToolCallDiffView: View {
    let diff: ACPToolCallDiff

    private var lines: [DiffLine] {
        ToolCallDiffLines.compute(old: diff.oldText, new: diff.newText)
    }

    private var addedCount: Int { lines.filter { $0.kind == .added }.count }
    private var removedCount: Int { lines.filter { $0.kind == .removed }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: diff.isCreation ? "doc.badge.plus" : "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text((diff.path as NSString).lastPathComponent)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if diff.isCreation {
                    Text("New file")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("+\(addedCount) -\(removedCount)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    diffLineView(line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("toolcall-diff-\((diff.path as NSString).lastPathComponent)")
    }

    @ViewBuilder
    private func diffLineView(_ line: DiffLine) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(gutter(for: line.kind))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(foreground(for: line.kind))
                .frame(width: 10, alignment: .center)
            Text(line.kind == .gap ? "⋯" : line.text)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(foreground(for: line.kind))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(background(for: line.kind))
    }

    private func gutter(for kind: DiffLine.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .removed: return "-"
        case .unchanged: return " "
        case .gap: return " "
        }
    }

    private func foreground(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        case .unchanged: return .primary
        case .gap: return .secondary
        }
    }

    private func background(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return Color.green.opacity(0.12)
        case .removed: return Color.red.opacity(0.12)
        case .unchanged, .gap: return .clear
        }
    }
}
