import SwiftUI

/// Transcript tab. Not yet designed (handover §1): this applies the design
/// tokens to speaker blocks and supports jumping to a timestamp.
struct TranscriptPane: View {
    let blocks: [TranscriptBlock]
    /// Timestamp to scroll to (set by timestamp links in the summary).
    @Binding var scrollTarget: Int64?

    var body: some View {
        if blocks.isEmpty {
            Text("No transcript for this meeting.")
                .font(.inter(15))
                .foregroundColor(Theme.textMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(blocks) { block in
                            TranscriptBlockRow(block: block, isTarget: block.id == highlightedId)
                                .id(block.id)
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
                }
                .onAppear { scroll(proxy) }
                .onChange(of: scrollTarget) { _ in scroll(proxy) }
            }
        }
    }

    private var highlightedId: Int64? {
        scrollTarget.flatMap { TranscriptBlocks.blockId(containing: $0, in: blocks) }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let id = highlightedId else { return }
        // Let the lazy stack lay out before scrolling.
        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .top) }
    }
}

private struct TranscriptBlockRow: View {
    let block: TranscriptBlock
    let isTarget: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.speakerColor(for: block.speakerId))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(block.label)
                    .font(.inter(13, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text(Date.formatTimestamp(ms: block.startMs))
                    .font(.mono(11))
                    .foregroundColor(isTarget ? Theme.accentText : Theme.textMuted)
            }
            Text(block.text)
                .font(.inter(15))
                .lineSpacing(4)
                .foregroundColor(Theme.ink2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 16)
        }
        .padding(.vertical, isTarget ? 8 : 0)
        .padding(.horizontal, isTarget ? 10 : 0)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(isTarget ? Theme.ground : .clear)
        )
        .accessibilityElement(children: .combine)
    }
}
