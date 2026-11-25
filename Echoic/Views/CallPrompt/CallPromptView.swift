import SwiftUI

/// "Zoom call started — Record it with Echoic?" (call-detection handover §3).
/// 420 x 84 ink card; shown in a floating panel when the menu is closed.
struct CallPromptView: View {
    let title: String
    let subtitle: String
    let onRecord: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            AppMark(size: 26, color: .white, dotColor: Theme.accentOnDark)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.display(15))
                    .foregroundColor(Theme.darkText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.inter(13))
                    .foregroundColor(Theme.darkText2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onRecord) {
                HStack(spacing: 8) {
                    Circle().fill(Theme.recordDot).frame(width: 9, height: 9).accessibilityHidden(true)
                    Text("Record")
                }
            }
            .buttonStyle(PromptRecordButtonStyle())
            .accessibilityLabel("Record this call")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.darkText2)
                    .frame(width: 36, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not now")
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.ink))
        .shadow(color: Theme.ink.opacity(0.28), radius: 16, x: 0, y: 12)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Call detected")
    }

    static let size = CGSize(width: 420, height: 84)
}

/// White, 40pt, radius 10, ink Inter 14 semibold.
private struct PromptRecordButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(14, weight: .semibold))
            .foregroundColor(Theme.ink)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
