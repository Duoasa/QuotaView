import AppKit
import QuotaViewCore
import SwiftUI

// Shared rhythm for detail pages; sidebar navigation keeps its own compact metrics.
enum SettingsLayoutMetrics {
    static let pageTopInset: CGFloat = 24
    static let pageBottomInset: CGFloat = 28
    static let sectionSpacing: CGFloat = 24
    static let itemSpacing: CGFloat = 12
    static let headingSpacing: CGFloat = 8
    static let cardInset: CGFloat = 10
    static let cardCornerRadius: CGFloat = 12
    static let rowMinHeight: CGFloat = 52
    static let rowVerticalInset: CGFloat = 8
    static let detailIconSize: CGFloat = 20
    static let agentIconSize: CGFloat = 26
    static let iconGap: CGFloat = 11
    static let iconInset: CGFloat = 11
    static let titleFont = Font.system(size: 13, weight: .medium)
    static let detailFont = Font.system(size: 12)
    static let choiceWidth: CGFloat = 276
    static let previewBottomInset: CGFloat = 28
}

extension SettingsView {
    func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.headingSpacing) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, SettingsLayoutMetrics.cardInset)
            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.itemSpacing, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    func preferenceToggle(
        _ title: String,
        subtitle: String? = nil,
        symbol: String,
        isOn: Binding<Bool>
    ) -> some View {
        NativeSettingsRow(
            title: title,
            subtitle: subtitle,
            symbol: symbol
        ) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

private struct NativeSettingsSidebarSurface: ViewModifier {
    let fallbackCornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    Glass.regular,
                    in: ConcentricRectangle()
                )
                .clipShape(ConcentricRectangle())
        } else {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(
                        cornerRadius: fallbackCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: fallbackCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(
                        Color(nsColor: .separatorColor),
                        lineWidth: 0.75
                    )
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: fallbackCornerRadius,
                        style: .continuous
                    )
                )
        }
    }
}

private extension View {
    func nativeSettingsSidebarSurface(
        fallbackCornerRadius: CGFloat
    ) -> some View {
        modifier(
            NativeSettingsSidebarSurface(
                fallbackCornerRadius: fallbackCornerRadius
            )
        )
    }
}

extension View {
    func nativeSettingsActionStyle() -> some View {
        self.buttonStyle(SettingsActionButtonStyle())
    }

}

private struct CodexActivityPreviewOptionButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(
                backgroundColor(isPressed: configuration.isPressed),
                in: RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
                .strokeBorder(
                    isSelected
                        ? Color(nsColor: .controlAccentColor)
                        : Color(nsColor: .separatorColor),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            }
            .scaleEffect(
                !reduceMotion && configuration.isPressed
                    ? 0.985
                    : 1
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.08),
                value: configuration.isPressed
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color(nsColor: .controlAccentColor).opacity(0.14)
        }
        if isSelected {
            return Color(nsColor: .controlAccentColor).opacity(0.10)
        }
        if isHovered {
            return Color(nsColor: .controlAccentColor).opacity(0.05)
        }
        return SettingsPalette.canvas
    }
}

private struct CodexActivityTimingControl: View {
    let title: String
    let subtitle: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let secondsLabel: String

    private var values: [Int] {
        Array(stride(
            from: range.lowerBound,
            through: range.upperBound,
            by: step
        ))
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { value = Int($0.rounded()) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 18)

                Text("\(value) \(secondsLabel)")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 58, alignment: .trailing)
            }

            Slider(
                value: sliderValue,
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .controlSize(.small)
            .accessibilityLabel(title)
            .accessibilityValue("\(value) \(secondsLabel)")

            HStack(alignment: .top, spacing: 0) {
                ForEach(values, id: \.self) { tick in
                    VStack(spacing: 3) {
                        Rectangle()
                            .fill(Color(nsColor: .tertiaryLabelColor))
                            .frame(
                                width: 1,
                                height: tick.isMultiple(of: 15) ? 6 : 4
                            )

                        if tick == range.lowerBound
                            || tick == range.upperBound
                        {
                            Text("\(tick)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        } else {
                            Color.clear.frame(height: 11)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}

extension EnvironmentValues {
    @Entry var settingsDetailIconSize: CGFloat = SettingsLayoutMetrics.detailIconSize
}

private struct SettingsDetailIcon: View {
    let symbol: String
    @Environment(\.settingsDetailIconSize) private var size

    var body: some View {
        SettingsSidebarIcon(
            symbol: symbol,
            color: Color(nsColor: .systemGray),
            size: size
        )
    }
}

struct SettingsSidebarIcon: View {
    let symbol: String
    let color: Color
    // Scale the artwork proportionally for sidebar and settings rows.
    var size: CGFloat = 20
    @Environment(\.colorSchemeContrast) private var contrast

    private var inset: CGFloat { (size * 3 / 22).rounded() }
    private var symbolSize: CGFloat { size - inset * 2 }
    private var cornerRadius: CGFloat { size * 5 / 22 }

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: symbolSize, height: symbolSize)
            .padding(inset)
            .frame(width: size, height: size)
            .fixedSize()
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(color.gradient)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(contrast == .increased ? 0.6 : 0.18), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

// A pop-up selection control lets AppKit position and highlight the selected item.
struct SettingsValueMenu<Selection: Hashable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Selection
    let options: [(Selection, String)]
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection, options: options) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.controlSize = .small
        button.font = .systemFont(ofSize: 13)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectItem(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.options = options
        let titles = options.map { $0.1 }
        if button.itemTitles != titles {
            button.removeAllItems()
            // Add individual items so distinct values may share a localized label.
            for title in titles {
                button.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
            }
        }
        button.selectItem(at: options.firstIndex { $0.0 == selection } ?? -1)
        button.isEnabled = isEnabled && !options.isEmpty
        button.setAccessibilityLabel(title)
        button.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        let size = nsView.intrinsicContentSize
        return CGSize(width: size.width, height: max(24, size.height))
    }

    final class Coordinator: NSObject {
        var selection: Binding<Selection>
        var options: [(Selection, String)]

        init(selection: Binding<Selection>, options: [(Selection, String)]) {
            self.selection = selection
            self.options = options
        }

        @objc func selectItem(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard options.indices.contains(index) else { return }
            selection.wrappedValue = options[index].0
        }
    }
}

struct SettingsActionButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        let color = configuration.role == .destructive ? Color(nsColor: .systemRed)
            : prominent ? Color(nsColor: .controlAccentColor) : Color.primary
        configuration.label.font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(color.opacity(configuration.isPressed ? 0.15 : hovered ? 0.10 : 0.06),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous)).opacity(enabled ? 1 : 0.4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .onHover { hovered = enabled && $0 }
            .onChange(of: enabled) { _, value in if !value { hovered = false } }
            .onDisappear { hovered = false }
    }
}

private struct SettingsNavigationButtonStyle: ButtonStyle {
    let selected: Bool
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.primary)
            .background(Color.primary.opacity(configuration.isPressed ? 0.13 : selected ? 0.10 : hovered ? 0.05 : 0),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous)).onHover { hovered = $0 }
            .onDisappear { hovered = false }
    }
}

private struct SettingsVisualOptionStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.primary).padding(12)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.06 : 0.025),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color(nsColor: .controlAccentColor) : Color(nsColor: .separatorColor), lineWidth: selected ? 1.5 : 0.5)
            }.contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .onHover { hovered = $0 }.onDisappear { hovered = false }
    }
}

/// Both providers use the same status and disclosure layout; their capabilities stay independent.
struct NativeSettingsConnectionStatus: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 5, height: 5).accessibilityHidden(true)
            Text(title).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct NativeSettingsConnectionDetails<Content: View>: View {
    let copy: AppCopy
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(copy.text("连接详情", "Connection Details"))
                .font(SettingsLayoutMetrics.titleFont)
        }
        .settingsRowInsets()
    }
}

struct SettingsChoiceRow<Choices: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let choices: () -> Choices

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: SettingsLayoutMetrics.iconGap) {
                SettingsDetailIcon(symbol: symbol)
                Text(title).font(SettingsLayoutMetrics.titleFont)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            HStack(alignment: .top, spacing: 12, content: choices)
                .frame(width: SettingsLayoutMetrics.choiceWidth)
        }
        .settingsRowInsets()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

enum SettingsPalette {
    // sRGB surfaces sampled from the supplied macOS Settings reference.
    static let canvas = adaptive(light: NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1),
                                 dark: NSColor(srgbRed: 34/255, green: 35/255, blue: 46/255, alpha: 1))
    static let group = adaptive(light: .controlBackgroundColor,
                                dark: NSColor(srgbRed: 41/255, green: 42/255, blue: 52/255, alpha: 1))
    static let sidebarTint = adaptive(light: .clear,
                                      dark: NSColor(srgbRed: 37/255, green: 39/255, blue: 60/255, alpha: 0.82))

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

private struct SettingsGroupSurface: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
            .fill(SettingsPalette.group)
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }
            }
            .allowsHitTesting(false)
    }
}

struct NativeSettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity)
        .background { SettingsGroupSurface() }
        .clipShape(
            RoundedRectangle(
                cornerRadius: SettingsLayoutMetrics.cardCornerRadius,
                style: .continuous
            )
        )
    }
}

extension View {
    func settingsRowInsets() -> some View {
        padding(.leading, SettingsLayoutMetrics.iconInset)
            .padding(.trailing, SettingsLayoutMetrics.cardInset)
            .padding(.vertical, SettingsLayoutMetrics.rowVerticalInset)
            .frame(maxWidth: .infinity, minHeight: SettingsLayoutMetrics.rowMinHeight)
    }
}

struct SettingsListRow<Icon: View, Control: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: SettingsLayoutMetrics.iconGap) {
            icon()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(SettingsLayoutMetrics.titleFont).foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle).font(SettingsLayoutMetrics.detailFont).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control().controlSize(.small)
        }
        .settingsRowInsets()
        .contentShape(Rectangle())
    }
}

struct NativeSettingsRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    @ViewBuilder let control: () -> Control

    var body: some View {
        SettingsListRow(title: title, subtitle: subtitle) {
            if let symbol { SettingsDetailIcon(symbol: symbol) }
        } control: {
            control()
        }
    }
}

struct NativeSettingsSegmentedPicker<
    Selection: Hashable,
    Content: View
>: View {
    let title: String
    @Binding var selection: Selection
    let content: Content

    init(
        _ title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        _selection = selection
        self.content = content()
    }

    var body: some View {
        Picker(title, selection: $selection) {
            content
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct NativeSettingsDivider: View {
    var body: some View {
        Rectangle().fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .padding(.horizontal, SettingsLayoutMetrics.cardInset)
            .accessibilityHidden(true)
    }
}

struct NativeSettingsNote: View {
    let text: String
    var horizontalPadding: CGFloat = SettingsLayoutMetrics.cardInset

    var body: some View {
        Text(text)
            .font(SettingsLayoutMetrics.detailFont)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
