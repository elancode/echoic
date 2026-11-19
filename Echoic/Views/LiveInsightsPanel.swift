import SwiftUI

/// Side panel in the Live Transcript window: a running recap plus the open
/// concerns and questions in the current discussion, from the live insights agent.
struct LiveInsightsPanel: View {
    @ObservedObject private var coordinator = MeetingCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LiveInsightsHeader(
                status: coordinator.liveInsightsStatus,
                updatedAt: coordinator.liveInsight.map { Date(timeIntervalSince1970: Double($0.createdAt) / 1000) },
                canRefresh: coordinator.state == .recording
                    && [.waiting, .failed].contains(coordinator.liveInsightsStatus),
                onRefresh: coordinator.refreshInsights
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MeetingContextField(text: $coordinator.meetingContextNote)
                    if let insight = coordinator.liveInsight {
                        LiveInsightContent(insight: insight)
                    } else {
                        LiveInsightsEmptyState(status: coordinator.liveInsightsStatus)
                    }
                }
                .padding(14)
                .textSelection(.enabled)
            }
        }
        .frame(minWidth: 240, idealWidth: 300)
    }
}

// MARK: - Header

private struct LiveInsightsHeader: View {
    let status: LiveInsightsStatus
    let updatedAt: Date?
    let canRefresh: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)
            Text("Insights")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            statusLabel
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(!canRefresh)
            .help("Update insights now")
            .accessibilityLabel("Update insights now")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .updating:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Updating insights")
        case .failed:
            Text("Couldn't update. Retrying next cycle.")
                .font(.system(size: 10))
                .foregroundColor(.orange)
        case .waiting, .disabled, .needsAPIKey:
            if let updatedAt {
                (Text("Updated ") + Text(updatedAt, style: .relative) + Text(" ago"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Context Note

private struct MeetingContextField: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What's this meeting about?")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            TextField("Optional, e.g. \"Decide the Q3 launch date\"", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .lineLimit(1...3)
                .accessibilityLabel("Meeting context for insights")
        }
    }
}

// MARK: - Content

private struct LiveInsightContent: View {
    let insight: LiveInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InsightSection(title: "Recap", systemImage: "text.alignleft") {
                Text(insight.recap)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            InsightSection(title: "Open concerns", systemImage: "exclamationmark.triangle") {
                InsightList(items: insight.concerns, emptyText: "No open concerns right now.")
            }
            InsightSection(title: "Questions", systemImage: "questionmark.bubble") {
                InsightList(items: insight.questions, emptyText: "No open questions right now.")
            }
        }
    }
}

private struct InsightSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            content
        }
    }
}

private struct InsightList: View {
    let items: [String]
    let emptyText: String

    var body: some View {
        if items.isEmpty {
            Text(emptyText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundColor(.secondary)
                        Text(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }
}

// MARK: - Empty State

private struct LiveInsightsEmptyState: View {
    let status: LiveInsightsStatus

    var body: some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var message: String {
        switch status {
        case .needsAPIKey:
            return "Add an Anthropic API key in Settings to get live insights."
        case .disabled:
            return "Insights appear here while a meeting is being recorded."
        case .waiting, .updating:
            return "Insights appear after a minute or two of discussion."
        case .failed:
            return "Couldn't reach Claude. Insights will retry on the next cycle."
        }
    }
}
