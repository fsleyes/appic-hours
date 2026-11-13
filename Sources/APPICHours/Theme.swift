import SwiftUI
import TrackerCore

// MARK: - Category styling

extension HourCategory {
    var color: Color {
        switch self {
        case .intervention: return .blue
        case .assessment: return .purple
        case .supervision: return .orange
        case .support: return .teal
        }
    }
    var icon: String {
        switch self {
        case .intervention: return "bubble.left.and.bubble.right.fill"
        case .assessment: return "list.bullet.clipboard.fill"
        case .supervision: return "person.2.fill"
        case .support: return "doc.text.fill"
        }
    }
}

func modalityIcon(_ m: String) -> String {
    switch m {
    case "Telehealth (video)": return "video.fill"
    case "Telephone": return "phone.fill"
    default: return "person.fill"
    }
}

func hoursText(_ minutes: Int) -> String { AAPI.fmt(Double(minutes) / 60) }

// MARK: - Surfaces

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

struct CardTitle: View {
    var title: String
    var icon: String? = nil
    var subtitle: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let icon { Image(systemName: icon).foregroundStyle(.secondary) }
            Text(title).font(.headline)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Small components

struct Pill: View {
    var text: String
    var color: Color = .secondary
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
    }
}

struct CategoryDot: View {
    var category: HourCategory
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(category.color).frame(width: 8, height: 8)
            Text(category.label)
        }
    }
}

struct Avatar: View {
    var name: String
    var size: CGFloat = 32
    var isGroup = false

    private var initials: String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "-" }).prefix(2)
        let s = parts.count > 1 ? parts.map { String($0.prefix(1)) }.joined() : String(name.prefix(2))
        return s.uppercased()
    }
    private var hue: Double {
        Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 360) / 360
    }
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(
                colors: [Color(hue: hue, saturation: 0.45, brightness: 0.9),
                         Color(hue: hue, saturation: 0.6, brightness: 0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            if isGroup {
                Image(systemName: "person.3.fill").font(.system(size: size * 0.36)).foregroundStyle(.white)
            } else {
                Text(initials).font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

struct ChipButton: View {
    var title: String
    var isOn: Bool
    var color: Color = .accentColor
    var icon: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).imageScale(.small) }
                Text(title).lineLimit(1)
            }
            .font(.callout.weight(isOn ? .semibold : .regular))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .contentShape(Capsule())
            // Liquid Glass: a tappable glass capsule; the selected chip is tinted glass.
            .glassEffect(isOn ? .regular.tint(color).interactive() : .regular.interactive(), in: .capsule)
            // a coloured outline keeps the selection visible even when the window is inactive
            .overlay(Capsule().strokeBorder(color.opacity(isOn ? 0.9 : 0), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: isOn)
    }
}

struct StatCard: View {
    var title: String
    var value: String
    var unit: String = "h"
    var icon: String
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).font(.callout).foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.callout).foregroundStyle(.secondary)
            }
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

/// Wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: proposal.width ?? width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > bounds.width { x = 0; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

/// Label column + content, for custom forms inside cards.
struct FieldRow<Content: View>: View {
    var label: String
    var alignment: VerticalAlignment = .center
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: alignment, spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 92, alignment: .trailing)
                .padding(.top, alignment == .top ? 4 : 0)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct EmptyHint: View {
    var title: String
    var icon: String
    var message: String
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
    }
}

/// Date <-> ISO helpers for SwiftUI bindings.
extension Binding where Value == Date {
    static func iso(_ get: @escaping () -> String?, _ set: @escaping (String) -> Void) -> Binding<Date> {
        Binding(get: { get().flatMap(Day.date) ?? Date() }, set: { set(Day.iso($0)) })
    }
}

// Clients and groups share numeric ids, so lists mixing both need distinct row keys.
extension Client { var rowKey: String { "c\(id)" } }
extension ClientGroup { var rowKey: String { "g\(id)" } }

/// Type-erased label style, so a view can switch between icon-only and title+icon.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

extension ClientKind {
    var icon: String { self == .therapy ? "bubble.left.and.bubble.right.fill" : "list.bullet.clipboard.fill" }
}

// MARK: - Hours ticker

/// An hours figure whose digits roll like an odometer when it changes; a "+1.5 h" chip pops up on increases.
struct HoursTicker: View {
    var minutes: Int
    var font: Font = .system(size: 22, weight: .semibold, design: .rounded)
    var unit: String? = "h"
    var showDelta = false
    @State private var delta: Int?
    @State private var bump = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(hoursText(minutes)).font(font).monospacedDigit()
                .contentTransition(.numericText(value: Double(minutes)))
                .scaleEffect(bump ? 1.08 : 1, anchor: .leading)
            if let unit { Text(unit).foregroundStyle(.secondary) }
            if let delta {
                Text("+\(hoursText(delta)) h")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .foregroundStyle(.green)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
            }
        }
        .animation(.spring(response: 0.8, dampingFraction: 0.82), value: minutes)
        .onChange(of: minutes) { old, new in
            guard showDelta, new > old else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { delta = new - old; bump = true }
            hideTask?.cancel()
            hideTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.spring(response: 0.4)) { bump = false }
                try? await Task.sleep(for: .seconds(2.4))
                if !Task.isCancelled { withAnimation(.easeOut(duration: 0.4)) { delta = nil } }
            }
        }
    }
}
