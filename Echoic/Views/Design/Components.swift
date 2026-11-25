import SwiftUI

// MARK: - Buttons

/// Ink buttons. Primary is solid ink (white on the dark popover); secondary is
/// outlined. Heights follow the handover: 32 toolbar, 44–48 popover actions.
struct InkButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    var kind: Kind = .primary
    var onDark = false
    var height: CGFloat = 32
    var radius: CGFloat = Theme.Radius.control
    var fullWidth = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(13, weight: .semibold))
            .foregroundColor(foreground)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: kind == .secondary ? 1 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
    }

    private var foreground: Color {
        switch (kind, onDark) {
        case (.primary, false): return .white
        case (.primary, true): return Theme.ink
        case (.secondary, false): return Theme.ink
        case (.secondary, true): return .white
        }
    }

    private var background: Color {
        switch (kind, onDark) {
        case (.primary, false): return Theme.ink
        case (.primary, true): return .white
        case (.secondary, false): return Theme.surface
        case (.secondary, true): return .clear
        }
    }

    private var borderColor: Color { onDark ? Theme.darkBorder : Theme.border }
}

/// A full-width menu row (Open library, Quit Echoic) with an optional shortcut hint.
struct MenuRow: View {
    let title: String
    var shortcut: String?
    var onDark = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.inter(13))
                    .foregroundColor(onDark ? .white : Theme.ink)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.mono(11))
                        .foregroundColor(onDark ? Theme.darkTextMuted : Theme.textMuted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tabs and filters

/// Segmented tabs on a chip track (Summary / Transcript).
struct SegmentedTabs<Tab: Hashable>: View {
    let tabs: [(tab: Tab, title: String)]
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.tab) { item in
                let isSelected = item.tab == selection
                Button { selection = item.tab } label: {
                    Text(item.title)
                        .font(.inter(13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? Theme.ink : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isSelected ? Theme.surface : .clear)
                                .shadow(color: isSelected ? Theme.ink.opacity(0.06) : .clear, radius: 1, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.pill + 1, style: .continuous).fill(Theme.chip))
        .accessibilityElement(children: .contain)
    }
}

/// Date filter pill (All, Today, This week, This month).
struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.inter(12, weight: .medium))
                .foregroundColor(isSelected ? Theme.ink : Theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .fill(isSelected ? Theme.surface : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .strokeBorder(isSelected ? Theme.border : .clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Labels

/// Mono uppercase group label ("Today", "Permissions").
struct GroupLabel: View {
    let title: String
    var onDark = false

    init(_ title: String, onDark: Bool = false) {
        self.title = title
        self.onDark = onDark
    }

    var body: some View {
        Text(title.uppercased())
            .font(.mono(11, weight: .medium))
            .tracking(0.66)
            .foregroundColor(onDark ? Theme.darkTextMuted : Theme.textMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Speaker chip. Unnamed speakers ("Speaker 3") get a dashed border and a
/// "Name" action — the entry point for naming a speaker.
struct SpeakerChip: View {
    let name: String
    let color: Color
    var isUnnamed = false
    var onName: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(name)
                .font(.inter(12, weight: .medium))
                .foregroundColor(Theme.ink)
            if isUnnamed, let onName {
                Button("Name", action: onName)
                    .buttonStyle(.plain)
                    .font(.inter(12, weight: .semibold))
                    .foregroundColor(Theme.accentText)
                    .accessibilityLabel("Name \(name)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(isUnnamed ? Theme.surface : Theme.chip))
        .overlay(
            Capsule().strokeBorder(
                Theme.border,
                style: StrokeStyle(lineWidth: isUnnamed ? 1 : 0, dash: [3, 2])
            )
        )
    }
}

// MARK: - Checkbox

/// Square ink checkbox with a title and optional caption.
struct InkCheckboxStyle: ToggleStyle {
    var onDark = false

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isOn ? (onDark ? Color.white : Theme.ink) : Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(configuration.isOn ? .clear : Theme.border, lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(onDark ? Theme.ink : .white)
                            .opacity(configuration.isOn ? 1 : 0)
                    )
                    .frame(width: 16, height: 16)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                configuration.label
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

// MARK: - Marks and indicators

/// Placeholder app mark: a dot with three fading arcs (not a finished logo).
struct AppMark: View {
    var size: CGFloat = 20
    var color: Color = Theme.ink

    var body: some View {
        Canvas { context, canvasSize in
            let unit = canvasSize.width / 20
            let center = CGPoint(x: 5 * unit, y: canvasSize.height / 2)
            let dot = CGRect(x: center.x - 2.5 * unit, y: center.y - 2.5 * unit, width: 5 * unit, height: 5 * unit)
            context.fill(Path(ellipseIn: dot), with: .color(color))
            for (index, radius) in [7.0, 11.0, 15.0].enumerated() {
                var arc = Path()
                arc.addArc(
                    center: center, radius: radius * unit,
                    startAngle: .degrees(-45), endAngle: .degrees(45), clockwise: false
                )
                let opacity = 0.8 - Double(index) * 0.25
                context.stroke(arc, with: .color(color.opacity(opacity)), lineWidth: 1.8 * unit)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The accent "live" dot. Pulses (1.6s ease-in-out opacity) unless Reduce
/// Motion is on — the only animation in the design.
struct LiveDot: View {
    var color: Color = Theme.accentFill
    var size: CGFloat = 8
    var pulses = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                guard pulses, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Card

extension View {
    /// White card with a soft border (Settings, popover sections).
    func inkCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.borderSoft, lineWidth: 1)
            )
    }
}
