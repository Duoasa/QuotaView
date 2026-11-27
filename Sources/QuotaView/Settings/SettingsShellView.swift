import AppKit
import QuotaViewCore
import SwiftUI

enum IslandSettingsPage: String, CaseIterable, Identifiable {
    case general, island, cards, usage, connections, proxy, feedback, about
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .island: "sparkles.rectangle.stack.fill"
        case .cards: "rectangle.stack.fill"
        case .usage: "chart.bar.fill"
        case .connections: "cpu.fill"
        case .proxy: "network"
        case .feedback: "ladybug.fill"
        case .about: "info.circle.fill"
        }
    }
    var color: NSColor {
        switch self {
        case .island, .connections: .systemBlue
        case .usage: .systemPurple
        case .feedback: .systemOrange
        default: .systemGray
        }
    }
    func title(_ copy: AppCopy) -> String {
        switch self {
        case .general: copy.text("通用与显示", "General & Display")
        case .island: copy.text("灵动岛", "Island")
        case .cards: copy.text("卡片设置", "Card settings")
        case .usage: copy.text("用量显示", "Usage display")
        case .connections: copy.text("Agent 接入", "Agent integration")
        case .proxy: copy.text("网络代理", "Network proxy")
        case .feedback: copy.text("Bug 反馈", "Bug feedback")
        case .about: copy.text("关于", "About")
        }
    }

}

enum SettingsDestination: Hashable {
    case page(IslandSettingsPage)
    case agent(IslandAgentProvider)

    var page: IslandSettingsPage {
        switch self {
        case .page(let page): page
        case .agent: .connections
        }
    }

    var agent: IslandAgentProvider? {
        if case .agent(let provider) = self { return provider }
        return nil
    }
}

struct SettingsNavigationHistory {
    private(set) var current = SettingsDestination.page(.general)
    private(set) var previous: [SettingsDestination] = []
    private(set) var next: [SettingsDestination] = []

    mutating func visit(_ destination: SettingsDestination) {
        guard destination != current else { return }
        previous.append(current)
        current = destination
        next.removeAll()
    }

    mutating func back() {
        guard let destination = previous.popLast() else { return }
        next.append(current)
        current = destination
    }

    mutating func forward() {
        guard let destination = next.popLast() else { return }
        previous.append(current)
        current = destination
    }
}

struct SettingsView: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var activityRuntime: CodexActivityRuntime
    @ObservedObject var updateController: AppUpdateController

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigation = SettingsNavigationHistory()
    @FocusState private var focusedPage: IslandSettingsPage?
    @State private var proxyDraft = ProxyConfiguration.default
    @State private var proxySaveFailure: ProxyConnectionFailure?
    @State private var codexConnectionDetailsExpanded = false
    @State private var showsQuitConfirmation = false
    @State private var showsFeedbackQRCode = false
    @State private var scrolledDestination: SettingsDestination?
    @State private var availableScreens = NSScreen.screens

    var copy: AppCopy { preferences.copy }

    var body: some View {
        ZStack {
            SettingsPalette.canvas
                .ignoresSafeArea()

            HStack(spacing: 0) {
                settingsSidebar
                    .frame(width: SettingsWindowMetrics.sidebarWidth)
                VStack(alignment: .leading, spacing: 0) {
                    SettingsPalette.canvas.frame(height: SettingsWindowMetrics.headerHeight)
                        .accessibilityHidden(true)
                    settingsDetail(for: navigation.current.page)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            availableScreens = NSScreen.screens
        }
        .environment(\.appLanguage, preferences.resolvedLanguage)
        .tint(Color(nsColor: .controlAccentColor))
        .buttonStyle(SettingsActionButtonStyle())
        .frame(
            minWidth: SettingsWindowMetrics.minimumContentSize.width,
            idealWidth: SettingsWindowMetrics.defaultContentSize.width,
            maxWidth: SettingsWindowMetrics.fixedContentWidth,
            minHeight: SettingsWindowMetrics.minimumContentSize.height,
            idealHeight: SettingsWindowMetrics.defaultContentSize.height
        )
        .containerShape(
            RoundedRectangle(
                cornerRadius: SettingsWindowMetrics.outerCornerRadius,
                style: .continuous
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: SettingsWindowMetrics.outerCornerRadius,
                style: .continuous
            )
        )
        .ignoresSafeArea(.container, edges: .top)
        .alert(copy.text("退出 QuotaView？", "Quit QuotaView?"), isPresented: $showsQuitConfirmation) {
            Button(copy.text("取消", "Cancel"), role: .cancel) {}
            Button(copy.text("退出", "Quit"), role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        } message: {
            Text(copy.text("Codex 任务会继续运行。", "Codex tasks will keep running."))
        }
        .sheet(isPresented: $showsFeedbackQRCode) {
            feedbackQRCode { showsFeedbackQRCode = false }
        }
        .background {
            SettingsWindowConfigurator(glassAppearance: preferences.islandGlassAppearance) {
                navigationHeader
                    .environment(\.locale, preferences.locale)
                    .environment(\.layoutDirection, layoutDirection)
            }
        }
    }

    private static let navigationGroups: [[IslandSettingsPage]] = [
        [.general, .island, .cards, .usage], [.connections, .proxy], [.feedback, .about]
    ]

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: SettingsWindowMetrics.headerHeight)
                .accessibilityHidden(true)
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(Array(Self.navigationGroups.enumerated()), id: \.offset) { index, group in
                        VStack(spacing: 4) {
                            ForEach(group) { page in settingsNavigationItem(page) }
                        }
                    }
                }.padding(.horizontal, 10).padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.top, 12)
            quitButton
                .padding([.horizontal, .bottom], SettingsWindowMetrics.quitButtonInset)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(SettingsPalette.sidebarTint)
                .ignoresSafeArea(edges: [.top, .bottom])
        }
    }

    private func settingsNavigationItem(_ page: IslandSettingsPage) -> some View {
        let selected = navigation.current.page == page
        return Button { navigation.visit(.page(page)); focusedPage = page } label: {
            HStack(spacing: 10) {
                SettingsSidebarIcon(symbol: page.symbol, color: Color(nsColor: page.color), size: 20)
                Text(page.title(copy))
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($focusedPage, equals: page)
        .help(page.title(copy))
        .accessibilityLabel(page.title(copy))
        .accessibilityValue(selected ? copy.text("已选择", "Selected") : "")
        .onKeyPress(.downArrow) { navigateSettings(from: page, offset: 1) }
        .onKeyPress(.upArrow) { navigateSettings(from: page, offset: -1) }
    }

    private func navigateSettings(from page: IslandSettingsPage, offset: Int) -> KeyPress.Result {
        let pages = IslandSettingsPage.allCases
        guard let index = pages.firstIndex(of: page) else { return .ignored }
        let next = pages[max(0, min(pages.count - 1, index + offset))]
        navigation.visit(.page(next)); focusedPage = next
        return .handled
    }

    private func settingsDetail(for page: IslandSettingsPage) -> some View {
        Group {
            if page == .island, #available(macOS 26.0, *) {
                scrollingSettings(for: page)
                    .scrollEdgeEffectHidden(true, for: .top)
            } else {
                scrollingSettings(for: page)
            }
        }
        .background(SettingsPalette.canvas)
        .id(navigation.current)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: navigation.current)
    }

    private func scrollingSettings(for page: IslandSettingsPage) -> some View {
        let destination = navigation.current
        return ScrollView {
            Group {
                if page == .island {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            settingsContent(for: page)
                        } header: {
                            islandStageVisual
                                .environment(\.colorScheme, .dark)
                                .frame(maxWidth: SettingsWindowMetrics.contentMaxWidth)
                                .frame(height: 210)
                                .padding(.horizontal, SettingsWindowMetrics.contentInset)
                                .padding(.top, SettingsLayoutMetrics.pageTopInset)
                                .padding(.bottom, SettingsLayoutMetrics.previewBottomInset)
                                .frame(maxWidth: .infinity)
                                .background(SettingsPalette.canvas)
                                .overlay(alignment: .bottom) {
                                    if scrolledDestination == destination {
                                        Divider().allowsHitTesting(false).accessibilityHidden(true)
                                    }
                                }
                        }
                    }
                } else {
                    settingsContent(for: page)
                }
            }
            .onGeometryChange(for: Bool.self) { content in
                content.frame(in: .scrollView(axis: .vertical)).minY < -0.5
            } action: { scrolled in
                guard navigation.current == destination else { return }
                scrolledDestination = scrolled ? destination : nil
            }
        }
    }

    private func settingsContent(for page: IslandSettingsPage) -> some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            switch page {
            case .general: generalSettings(availableScreens: availableScreens)
            case .island: islandSettings
            case .cards: cardSettings
            case .usage: usageSettings
            case .connections:
                connectionSettings(
                    selected: navigation.current.agent,
                    openAgent: { navigation.visit(.agent($0)) },
                    detailsExpanded: $codexConnectionDetailsExpanded
                ).environment(\.settingsDetailIconSize, SettingsLayoutMetrics.agentIconSize)
            case .proxy: proxySettings($proxyDraft: $proxyDraft, $proxySaveFailure: $proxySaveFailure)
            case .feedback: feedbackSettings { showsFeedbackQRCode = true }
            case .about: aboutSettings
            }
        }
        .frame(maxWidth: SettingsWindowMetrics.contentMaxWidth, alignment: .topLeading)
        .padding(.horizontal, SettingsWindowMetrics.contentInset)
        .padding(.top, page == .island ? SettingsLayoutMetrics.itemSpacing : SettingsLayoutMetrics.pageTopInset)
        .padding(.bottom, SettingsLayoutMetrics.pageBottomInset)
        .frame(maxWidth: .infinity)
    }

    private var navigationHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                historyButton("chevron.backward", title: copy.text("后退", "Back"), enabled: !navigation.previous.isEmpty) {
                    navigation.back()
                }
                .keyboardShortcut("[", modifiers: .command)
                Divider().frame(height: 14)
                historyButton("chevron.forward", title: copy.text("前进", "Forward"), enabled: !navigation.next.isEmpty) {
                    navigation.forward()
                }
                .keyboardShortcut("]", modifiers: .command)
            }
            .background {
                if #available(macOS 26, *) {
                    Color.clear
                        .glassEffect(.regular, in: Capsule())
                        .allowsHitTesting(false)
                } else {
                    Capsule().fill(.regularMaterial)
                        .overlay { Capsule().strokeBorder(.quaternary, lineWidth: 0.5) }
                        .allowsHitTesting(false)
                }
            }
            HStack(spacing: SettingsLayoutMetrics.iconGap) {
                if let agent = navigation.current.agent {
                    AgentSettingsIcon(provider: agent)
                }
                Text(navigation.current.agent?.displayName ?? navigation.current.page.title(copy))
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: SettingsWindowMetrics.headerHeight)
        .background(SettingsPalette.canvas)
        .overlay(alignment: .bottom) {
            if scrolledDestination == navigation.current {
                Divider().allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    private func historyButton(_ symbol: String, title: String, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
        .help(title)
    }

    private var quitButton: some View {
        Button(role: .destructive) { showsQuitConfirmation = true } label: {
            HStack(spacing: 8) {
                Text(copy.text("退出 QuotaView", "Quit QuotaView"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
        }
        .buttonStyle(IslandApprovalActionStyle(primary: false, destructive: true, emphasized: true,
            subtleDestructive: true, cornerRadius: SettingsWindowMetrics.quitButtonCornerRadius))
    }
}

/// Keep the navigation controls in the native title bar, above the full-size content view.
@MainActor
final class SettingsTitlebarHeader<Header: View> {
    private let accessory = NSTitlebarAccessoryViewController()
    private var hostingView: NSHostingView<Header>?
    private(set) weak var window: NSWindow?

    func update(_ header: Header, in window: NSWindow) {
        if let hostingView {
            hostingView.rootView = header
        } else {
            let view = NSHostingView(rootView: header)
            view.frame.size = NSSize(width: SettingsWindowMetrics.fixedContentWidth - SettingsWindowMetrics.sidebarWidth,
                                     height: SettingsWindowMetrics.headerHeight)
            accessory.layoutAttribute = .right
            accessory.view = view
            hostingView = view
        }
        guard self.window !== window else { return }
        detach()
        window.addTitlebarAccessoryViewController(accessory)
        self.window = window
    }

    func detach() {
        if let window, let index = window.titlebarAccessoryViewControllers.firstIndex(of: accessory) {
            window.removeTitlebarAccessoryViewController(at: index)
        }
        window = nil
    }
}

private struct SettingsWindowConfigurator<Header: View>: NSViewRepresentable {
    let glassAppearance: AppPreferences.IslandGlassAppearance
    let header: Header

    init(glassAppearance: AppPreferences.IslandGlassAppearance, @ViewBuilder header: () -> Header) {
        self.glassAppearance = glassAppearance
        self.header = header()
    }

    typealias Coordinator = SettingsTitlebarHeader<Header>

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(for: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(
        _ nsView: NSView,
        context: Context
    ) {
        DispatchQueue.main.async {
            configureWindow(
                for: nsView,
                coordinator: context.coordinator
            )
        }
    }

    private func configureWindow(
        for view: NSView,
        coordinator: Coordinator
    ) {
        guard let window = view.window else { return }

        window.styleMask.insert(.fullSizeContentView)
        SettingsWindowMetrics.applyAppearance(glassAppearance, to: window)
        SettingsWindowMetrics.configureTitlebar(of: window)
        window.isMovableByWindowBackground = true
        SettingsWindowMetrics.applyOuterShape(to: window)
        window.hasShadow = true
        SettingsWindowMetrics.applySizingPolicy(to: window)

        if coordinator.window !== window {
            window.setContentSize(SettingsWindowMetrics.defaultContentSize)
        }
        coordinator.update(header, in: window)
    }
}
