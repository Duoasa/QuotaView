import AppKit
import SwiftUI
import QuotaViewCore

// DEBUG-ONLY-MOCK: isolated manual console. Never constructs the production delegate.
@main
struct IslandTextConsoleApp: App {
    @NSApplicationDelegateAdaptor(IslandTextConsoleDelegate.self) var delegate
    init() { AstaSansFontRegistrar.registerBundledFonts() }
    var body: some Scene {
        WindowGroup("灵动岛动效开发台 · DEBUG") { IslandTextConsoleView() }
            .defaultSize(width: 1040, height: 800)
    }
}

final class IslandTextConsoleDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
private final class TextConsoleModel: ObservableObject {
    @Published var state: CodexActivityVisualState = .completed
    @Published var english = false
    @Published var progress = 35.0
    @Published var quota = 27
    @Published var quotaAvailable = true
    @Published var tokensAvailable = true
    @Published var tokenInput = "783800"
    @Published var title = "检查百分号显示 / Check quota text"
    @Published var operation = "正在检查文字宽度 / Checking text layout"
    @Published var customStatus = ""
    @Published var customToken = ""
    @Published var paused = false
    @Published var reduceMotion = false
    @Published var hover = false
    @Published var reminder = false
    @Published var presentation: CodexActivityIslandPresentation = .expanded
    @Published var visible = true
    @Published var effect: AppPreferences.CodexActivityProgressEffect = .dropField
    @Published var playing = false
    @Published var elapsed = 0.0
    @Published var generation: UInt64 = 0
    private var task: Task<Void, Never>?

    var copy: CodexActivityCopy { .init(language: english ? .english : .simplifiedChinese) }
    var tokens: Int64? {
        guard tokensAvailable, let count = Int64(tokenInput), count > 0 else { return nil }
        return count
    }
    var effectiveProgress: Double {
        switch state {
        case .completed: return 1
        case .standby, .unavailable, .disconnectedCodex: return 0
        default: return min(max(progress, 0), 95) / 100
        }
    }
    var renderState: CodexActivityRenderState {
        let receipt = state == .completed && tokens != nil
        let status = customStatus.isEmpty ? copy.statusTitle(for: state) : customStatus
        let tokenText = tokens.map { customToken.isEmpty ? copy.tokenUsageTitle(totalTokens: $0) : customToken }
        let detail = tokens.map { customToken.isEmpty ? copy.completionTokenUsageDetail(totalTokens: $0) : customToken }
        return .init(
            taskIdentity: .init(sessionHash: "text-console-debug", turnHash: "manual", generation: generation),
            visualState: state, approximateProgressFraction: effectiveProgress,
            windowTitle: title, statusTitle: status, operation: operation,
            tokenUsageTitle: tokenText,
            completionReceiptStatus: receipt ? status : nil,
            completionReceiptDetail: receipt ? detail : nil,
            completionQuotaRemainingPercent: receipt && quotaAvailable ? quota : nil,
            isConfirmationReminderActive: state == .awaitingConfirmation && reminder,
            accessibilityLabel: "仅用于调试 / DEBUG · \(status) · \(tokenText ?? "—") · \(quotaAvailable ? String(quota) : "—")%"
        )
    }
    func stop() { task?.cancel(); task = nil; playing = false }
    func select(_ newState: CodexActivityVisualState) {
        stop(); generation &+= 1; state = newState
    }
    func preset(_ name: String) {
        stop(); generation &+= 1
        customStatus = ""; customToken = ""; tokensAvailable = true; quotaAvailable = true
        tokenInput = "783800"; reminder = false
        switch name {
        case "long":
            state = .working
            title = String(repeating: "超长任务标题 👩🏽‍💻 cafe\u{301} / Long title · ", count: 4)
            operation = String(repeating: "Running tool → 正在执行步骤 / ", count: 4)
            customToken = "本次 999999999999999999999 tokens this turn"
        case "missing": state = .completed; quotaAvailable = false
        case "noTokens": state = .working; tokensAvailable = false
        default:
            state = .completed; quota = 27
            title = "检查百分号显示 / Check quota text"
            operation = "正在检查文字宽度 / Checking text layout"
        }
    }
    func playDemo() {
        preset("normal"); paused = false; presentation = .expanded; visible = true; playing = true; elapsed = 0
        task = Task { @MainActor [weak self] in
            let started = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self else { return }
                elapsed = min(20, ProcessInfo.processInfo.systemUptime - started)
                switch elapsed {
                case ..<3: state = .thinking; progress = 12
                case ..<6: state = .working; progress = 40
                case ..<9: state = .compactingContext; progress = 55
                case ..<12: state = .awaitingConfirmation; reminder = true; progress = 65
                case ..<14: state = .error; progress = 65
                case ..<16: state = .working; progress = 95
                case ..<18: state = .completed; quota = 27
                case ..<19: state = .completed; quota = 25
                default: state = .completed; quota = 100
                }
                if elapsed >= 20 { playing = false; task = nil; return }
                do { try await Task.sleep(nanoseconds: 100_000_000) }
                catch { return }
            }
        }
    }
}

private struct IslandTextConsoleView: View {
    @StateObject private var model = TextConsoleModel()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private func manual<Value>(_ key: ReferenceWritableKeyPath<TextConsoleModel, Value>) -> Binding<Value> {
        Binding(get: { model[keyPath: key] }, set: { model.stop(); model[keyPath: key] = $0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("灵动岛动效开发台").font(.title2.bold())
                    Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") Build \(Bundle.main.object(forInfoDictionaryKey: "QuotaViewDisplayBuildNumber") as? String ?? "—") · 系统顶部弹性呼出 · 仅用于调试 / DEBUG")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("English 文案", isOn: manual(\.english)).toggleStyle(.switch).fixedSize()
            }
            HStack(spacing: 12) {
                Picker("尺寸", selection: manual(\.presentation)) {
                    Text("展开").tag(CodexActivityIslandPresentation.expanded)
                    Text("缩略").tag(CodexActivityIslandPresentation.compact)
                }.pickerStyle(.segmented).frame(width: 220).disabled(!model.visible)
                Button("呼出") { model.stop(); model.presentation = .expanded; model.visible = true }
                    .disabled(model.visible)
                Button("隐藏") { model.stop(); model.visible = false }
                    .disabled(!model.visible)
                Spacer()
                Text(model.visible ? "\(model.presentation == .expanded ? "展开" : "缩略") · DEBUG" : "已隐藏 · DEBUG")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextIslandPreview(state: model.renderState, presentation: model.presentation,
                visible: model.visible, effect: model.effect,
                reduceMotion: model.reduceMotion || systemReduceMotion,
                playback: !model.paused, hover: model.hover)
                .frame(maxWidth: .infinity).frame(height: 1)
                .accessibilityHidden(true)
            Text("预览在当前屏幕的系统状态栏下方。呼出从小到大冒出并弹性回稳；隐藏先缩略，再收起。")
                .font(.caption).foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                        ForEach(CodexActivityVisualState.allCases, id: \.rawValue) { state in
                            Button(model.copy.statusTitle(for: state)) { model.select(state) }
                                .buttonStyle(.bordered).tint(model.state == state ? .accentColor : nil)
                                .frame(maxWidth: .infinity)
                                .help("DEBUG · 切换模拟状态")
                        }
                    }
                    HStack {
                        Text("完成额度").frame(width: 82, alignment: .leading)
                        Slider(value: Binding(get: { Double(model.quota) }, set: { model.stop(); model.quota = Int($0) }), in: 0...100, step: 1)
                            .disabled(!model.quotaAvailable)
                            .accessibilityLabel("DEBUG 完成态剩余额度")
                        Stepper("\(model.quota)%", value: manual(\.quota), in: 0...100)
                            .frame(width: 105).disabled(!model.quotaAvailable)
                        Toggle("额度可用", isOn: manual(\.quotaAvailable))
                    }
                    HStack {
                        Text("边界值").frame(width: 82, alignment: .leading)
                        ForEach([0, 1, 9, 10, 25, 26, 27, 28, 99, 100], id: \.self) { value in
                            Button("\(value)%") {
                                model.select(.completed); model.tokensAvailable = true
                                if model.tokens == nil { model.tokenInput = "783800" }
                                model.quotaAvailable = true; model.quota = value
                            }
                        }
                    }
                    HStack {
                        Text("运行进度").frame(width: 82, alignment: .leading)
                        Slider(value: manual(\.progress), in: 0...95, step: 1)
                            .accessibilityLabel("DEBUG 模拟任务进度")
                        Text("\(Int(model.effectiveProgress * 100))%").monospacedDigit().frame(width: 48)
                        Text("完成固定 100%").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    input("任务标题", text: manual(\.title))
                    input("操作说明", text: manual(\.operation))
                    input("自定状态", text: manual(\.customStatus), prompt: "留空使用当前语言的真实状态文案")
                    HStack {
                        input("Token 数值", text: manual(\.tokenInput))
                        Toggle("Token 可用", isOn: manual(\.tokensAvailable))
                    }
                    input("自定 Token", text: manual(\.customToken), prompt: "留空按数值自动格式化；可输入超长文本测试省略")
                    Text("关闭 Token 或数值无效时，按生产规则隐藏 Token；没有有效 Token 的完成态不展示成功回执。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("默认 · 27%") { model.preset("normal") }
                        Button("长标题 / Emoji / 超长 Token") { model.preset("long") }
                        Button("额度缺失 —") { model.preset("missing") }
                        Button("Token 缺失") { model.preset("noTokens") }
                        Spacer()
                    }
                    HStack {
                        Picker("特效", selection: manual(\.effect)) {
                            ForEach(AppPreferences.CodexActivityProgressEffect.allCases) { effect in
                                Text(effect.displayName.simplifiedChinese).tag(effect)
                            }
                        }.frame(width: 235)
                        Toggle("确认提醒", isOn: manual(\.reminder))
                        Toggle("减少动态效果", isOn: manual(\.reduceMotion))
                        Toggle("暂停特效", isOn: manual(\.paused))
                    }
                    HStack {
                        Toggle("模拟悬停透明", isOn: manual(\.hover))
                        Spacer()
                        Text("可把窗口移至其他显示器检查不同缩放倍率").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.trailing, 8)
            }
            Divider()
            HStack {
                Button("播放 20 秒完整 Demo") { model.playDemo() }.buttonStyle(.borderedProminent)
                Button("停止") { model.stop() }.disabled(!model.playing).keyboardShortcut(.escape, modifiers: [])
                Text(model.playing ? String(format: "%.1f / 20 秒", model.elapsed) : "手动模式")
                    .monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Text("DEBUG · 全部为模拟数据").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(minWidth: 980, minHeight: 690)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { model.stop() }
    }
    private func input(_ title: String, text: Binding<String>, prompt: String = "") -> some View {
        HStack {
            Text(title).frame(width: 82, alignment: .leading)
            TextField(prompt, text: text).textFieldStyle(.roundedBorder)
                .accessibilityLabel("DEBUG · \(title)")
        }
    }
}

private struct TextIslandPreview: NSViewRepresentable {
    let state: CodexActivityRenderState
    let presentation: CodexActivityIslandPresentation
    let visible: Bool
    let effect: AppPreferences.CodexActivityProgressEffect
    let reduceMotion: Bool
    let playback: Bool
    let hover: Bool
    func makeNSView(context: Context) -> TextIslandHost { .init(state: state) }
    func updateNSView(_ view: TextIslandHost, context: Context) {
        view.update(state: state, presentation: presentation, visible: visible, effect: effect,
                    reduceMotion: reduceMotion, playback: playback, hover: hover)
    }
    static func dismantleNSView(_ view: TextIslandHost, coordinator: ()) { view.stop() }
}

private final class TextIslandHost: NSView {
    private let island: ActivityIslandContentView
    private let previewPanel: NSPanel
    private let canvas = NSView()
    private var motion: ConsoleMotion?
    private var pose = ConsoleMotion.Pose(width: 462, height: 128, visibility: 1)
    private var layoutPose = ConsoleMotion.Pose(width: 462, height: 128, visibility: 1)
    private var textPose = ConsoleMotion.Pose(width: 462, height: 128, visibility: 1)
    private var transitionTimer: Timer?
    private var hover = false
    private var requestedPlayback = true
    private var observers: [NSObjectProtocol] = []
    private var stopped = false
    init(state: CodexActivityRenderState) {
        island = .init(initialState: state, progressEffect: .dropField)
        previewPanel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 210),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(frame: .zero)
        previewPanel.isReleasedWhenClosed = false
        previewPanel.isFloatingPanel = true
        previewPanel.hidesOnDeactivate = false
        // Keep the DEBUG preview above a running production island without stopping it.
        previewPanel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        previewPanel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        previewPanel.backgroundColor = .clear
        previewPanel.isOpaque = false
        previewPanel.hasShadow = false
        previewPanel.ignoresMouseEvents = true
        previewPanel.animationBehavior = .none
        canvas.wantsLayer = true
        canvas.layer?.masksToBounds = true
        canvas.addSubview(island)
        previewPanel.contentView = canvas
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit {
        transitionTimer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMoveNotification,
                         NSWindow.didChangeScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name,
                    object: window, queue: .main) { [weak self] _ in
                        self?.positionPanel()
                        self?.refreshPlayback()
                    })
            }
        }
        positionPanel()
        refreshPlayback()
    }
    func update(state: CodexActivityRenderState, presentation: CodexActivityIslandPresentation,
                visible: Bool, effect: AppPreferences.CodexActivityProgressEffect,
                reduceMotion: Bool, playback: Bool, hover: Bool) {
        requestedPlayback = playback
        stopped = false
        self.hover = hover
        let size = CodexActivityIslandGeometry.panelSize(presentation: presentation, renderState: state)
        island.setReduceMotion(reduceMotion)
        island.update(renderState: state, progressEffect: effect)
        island.setPresentationMode(presentation, accessibilityValue: "DEBUG · \(visible ? "显示" : "隐藏")")
        let inset = CodexActivityIslandGeometry.panelInset
        let target = visible ? ConsoleMotion.Pose(width: size.width, height: size.height, visibility: 1)
            : ConsoleMotion.hiddenPose(inset: inset)
        if motion == nil {
            motion = ConsoleMotion(pose: target)
            pose = target
            layoutPose = target
            textPose = target
        } else if motion?.target != target || reduceMotion {
            let now = ProcessInfo.processInfo.systemUptime
            let animated = !reduceMotion && isWindowVisible
            if !visible {
                let compactSize = CodexActivityIslandGeometry.panelSize(presentation: .compact, renderState: state)
                motion?.hide(compact: .init(width: compactSize.width, height: compactSize.height, visibility: 1),
                             inset: inset, at: now, animated: animated)
            } else {
                motion?.present(target, at: now, resizeDuration: presentation.transitionDuration,
                                elasticResize: presentation == .expanded, reduceMotion: !animated)
            }
            advanceTransition()
            if motion?.isAnimating(at: ProcessInfo.processInfo.systemUptime) == true {
                startTimer()
            }
        }
        refreshPlayback(); needsLayout = true
    }
    override func layout() {
        super.layout()
        positionPanel()
        renderPose()
    }
    private func positionPanel() {
        guard let screen = window?.screen else { return }
        let visibleFrame = screen.visibleFrame
        let frame = NSRect(x: visibleFrame.midX - 320, y: visibleFrame.maxY - 210, width: 640, height: 210)
        if previewPanel.frame != frame { previewPanel.setFrame(frame, display: false) }
    }
    private func renderPose() {
        let inset = CodexActivityIslandGeometry.panelInset
        island.setPresentationLayoutSize(NSSize(width: layoutPose.width, height: layoutPose.height))
        island.frame = pose.frame(in: canvas.bounds, inset: inset)
        island.setTextLayoutFrame(textPose.frame(relativeTo: layoutPose, inset: inset), opacity: textPose.visibility)
        island.alphaValue = pose.visibility * (hover
            ? CodexActivityIslandHoverTransparencyContract.hoveredAlpha : 1)
        island.isHidden = pose.visibility == 0
        island.layoutSubtreeIfNeeded()
    }
    private var isWindowVisible: Bool { window?.occlusionState.contains(.visible) ?? false }
    private func startTimer() {
        guard transitionTimer == nil else { return }
        let timer = Timer(timeInterval: 1 / 60.0, repeats: true) { [weak self] _ in self?.advanceTransition() }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        transitionTimer = timer
    }
    private func advanceTransition() {
        guard let motion else { return }
        let now = ProcessInfo.processInfo.systemUptime
        pose = motion.sample(at: now)
        layoutPose = motion.sampleLayout(at: now)
        textPose = motion.sampleText(at: now)
        renderPose()
        if !motion.isAnimating(at: now) {
            transitionTimer?.invalidate(); transitionTimer = nil
        }
        refreshPlayback()
    }
    func refreshPlayback() {
        guard !stopped else { return }
        if !isWindowVisible, let target = motion?.target {
            transitionTimer?.invalidate(); transitionTimer = nil
            motion = ConsoleMotion(pose: target)
            pose = target
            layoutPose = target
            textPose = target
            renderPose()
        }
        let shown = isWindowVisible && (pose.visibility > 0 || motion?.target.visibility == 1)
        if shown {
            if !previewPanel.isVisible { previewPanel.orderFrontRegardless() }
        } else {
            previewPanel.orderOut(nil)
        }
        island.setPlaybackVisible(requestedPlayback && shown)
    }
    func stop() {
        requestedPlayback = false
        stopped = true
        transitionTimer?.invalidate(); transitionTimer = nil
        island.setPlaybackVisible(false)
        previewPanel.orderOut(nil)
    }
}
