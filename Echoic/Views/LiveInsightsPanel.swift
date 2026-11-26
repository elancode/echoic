import SwiftUI

/// Insights panel in the Live Transcript window: the goal field, then the live
/// insights agent's recap, open concerns and questions (live transcript handover §5,
/// with today's insight content).
struct LiveInsightsPanel: View {
    @ObservedObject private var coordinator = MeetingCoordinator.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                InsightsTitleRow(
                    status: coordinator.liveInsightsStatus,
                    updatedAt: coordinator.liveInsight.map { Date(timeIntervalSince1970: Double($0.createdAt) / 1000) },
                    canRefresh: coordinator.state == .recording
                        && [.waiting, .failed].contains(coordinator.liveInsightsStatus),
                    onRefresh: coordinator.refreshInsights
                )
                GoalField(text: $coordinator.meetingContextNote)
                if let insight = coordinator.liveInsight {
                    InsightContent(insight: insight)
                } else {
                    Text(emptyMessage)
                        .font(.inter(14))
                        .foregroundColor(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .background(Theme.ground)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.borderSoft).frame(width: 1) }
    }

    private var emptyMessage: String {
        switch coordinator.liveInsightsStatus {
        case .needsAPIKey: return "Set up Claude in Settings → Claude to get live insights."
        case .disabled: return "Insights appear here while a meeting is being recorded."
        case .waiting, .updating: return "Insights appear after a minute or two of discussion."
        case .failed: return "Couldn't reach Claude. Insights will retry on the next cycle."
        }
    }
}

// MARK: - Title row

private struct InsightsTitleRow: View {
    let status: LiveInsightsStatus
    let updatedAt: Date?
    let canRefresh: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Insights").font(.display(16)).foregroundColor(Theme.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            statusText
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canRefresh)
            .opacity(canRefresh ? 1 : 0.4)
            .accessibilityLabel("Update insights now")
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch status {
        case .updating:
            Text("Updating…").font(.mono(11)).foregroundColor(Theme.textMuted)
        case .failed:
            Text("Couldn't update").font(.mono(11)).foregroundColor(Theme.accentText)
        case .waiting, .disabled, .needsAPIKey:
            if let updatedAt {
                TimelineView(.periodic(from: .now, by: 10)) { context in
                    Text("Updated \(Self.ago(updatedAt, now: context.date))")
                        .font(.mono(11))
                        .foregroundColor(Theme.textMuted)
                }
            }
        }
    }

    /// "20 s ago", "3 min ago".
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(max(seconds / 10 * 10, 5)) s ago" }
        return "\(seconds / 60) min ago"
    }
}

// MARK: - Goal

private struct GoalField: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupLabel("Goal for this meeting")
            TextField("Optional, e.g. Decide the launch date", text: $text)
                .textFieldStyle(.plain)
                .font(.inter(13))
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .accessibilityLabel("Goal for this meeting")
        }
    }
}

// MARK: - Content

private struct InsightContent: View {
    let insight: LiveInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                GroupLabel("So far")
                Text(insight.recap)
                    .font(.inter(15))
                    .lineSpacing(5)
                    .foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            InsightCards(title: "Open concerns", items: insight.concerns)
            InsightCards(title: "Open questions", items: insight.questions)
        }
    }
}

/// "OPEN QUESTIONS · 2" over white cards; "None yet." when empty.
private struct InsightCards: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupLabel("\(title) · \(items.count)")
            if items.isEmpty {
                Text("None yet.").font(.inter(14)).foregroundColor(Theme.textMuted)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(.inter(14))
                        .foregroundColor(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.surface))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                                .strokeBorder(Theme.borderSoft, lineWidth: 1)
                        )
                }
            }
        }
    }
}
