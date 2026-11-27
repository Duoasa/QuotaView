import AppKit
import CoreText
import SwiftUI
import QuotaViewCore

// Official Codex and Claude app icons retain their original transparent canvas.
// Other providers reuse the brand assets from the connection list.
struct IslandTaskProviderIcon: View {
    let provider: IslandAgentProvider
    var size: CGFloat = 16
    private var tileSize: CGFloat { size * 0.8 }

    var body: some View {
        Group {
            if let icon = IslandProviderIcon.settingsMark(for: provider) {
                if [IslandAgentProvider.codex, .claudeCode, .antigravity].contains(provider) {
                    Image(nsImage: icon).renderingMode(.original).resizable().scaledToFit()
                } else {
                    ZStack {
                        Color.white
                        Image(nsImage: icon).renderingMode(.original).resizable().scaledToFit()
                            .frame(width: provider == .kimiCode ? tileSize : tileSize * 16 / 22,
                                   height: provider == .kimiCode ? tileSize : tileSize * 16 / 22)
                    }
                    .frame(width: tileSize, height: tileSize)
                    .clipShape(RoundedRectangle(cornerRadius: tileSize * 5 / 22, style: .continuous))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(provider.displayName)
        .allowsHitTesting(false)
    }
}

// Native Metal draws independently of SwiftUI layout; hidden hosts never play.
private struct IslandActivityOrb: NSViewRepresentable {
    let visualState: CodexActivityVisualState
    let playback: Bool
    var completionPhase: IslandCardCompletionPhase? = nil
    func makeNSView(context: Context) -> IslandActivityOrbHost { .init(state: visualState) }
    func updateNSView(_ view: IslandActivityOrbHost, context: Context) {
        view.configure(state: visualState, playback: playback, completionPhase: completionPhase)
    }
    static func dismantleNSView(_ view: IslandActivityOrbHost, coordinator: ()) { view.stop() }
}

// Compact status and background memory share the same visible sphere size.
struct IslandSmallActivityOrb: View {
    let visualState: CodexActivityVisualState
    let playback: Bool
    var body: some View {
        IslandActivityOrb(visualState: visualState, playback: playback)
            .frame(width: 18, height: 18)
    }
}

private struct IslandQuantumProgress: NSViewRepresentable {
    let effect: AppPreferences.CodexActivityProgressEffect
    let renderState: CodexActivityRenderState
    let visible: Bool
    let reduceMotion: Bool
    let defersCompletionSkin: Bool
    let completionRiseStart: CFTimeInterval?
    let primaryContentHeight: CGFloat
    func makeNSView(context: Context) -> IslandQuantumProgressHost { .init(frame: .zero) }
    func updateNSView(_ view: IslandQuantumProgressHost, context: Context) {
        view.configure(renderState: renderState, visible: visible, reduceMotion: reduceMotion,
            progressEffect: effect, primaryContentHeight: primaryContentHeight, defersCompletionSkin: defersCompletionSkin,
            completionRiseStart: completionRiseStart)
    }
    static func dismantleNSView(_ view: IslandQuantumProgressHost, coordinator: ()) { view.stop() }
}

private struct IslandOperationLine: View {
    let renderState: CodexActivityRenderState
    let visible: Bool
    let reduceMotion: Bool
    var body: some View {
        let completed = renderState.visualState == .completed
        let running = [.working, .thinking, .compactingContext].contains(renderState.visualState)
        let copy = IslandOperationText(operation: renderState.operation,
                                        statusTitle: renderState.statusTitle, completed: completed)
        HStack(spacing: 5) {
            IslandScrollingText(text: copy.status,
                font: .systemFont(ofSize: IslandVibeLayout.operationFont, weight: .medium),
                color: NSColor(IslandBoardStyle.statusColor(renderState.visualState)),
                visible: visible, reduceMotion: reduceMotion, shimmer: running)
                .fixedSize()
            if !copy.detail.isEmpty {
                Text("·").font(.system(size: IslandVibeLayout.operationFont))
                    .foregroundStyle(IslandBoardStyle.muted).fixedSize()
                IslandScrollingText(text: copy.detail,
                    font: .systemFont(ofSize: IslandVibeLayout.operationFont, weight: .medium),
                    color: IslandTextPalette.detail,
                    visible: visible, reduceMotion: reduceMotion, shimmer: running)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }.accessibilityHint("\(copy.status) · \(copy.detail)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(copy.status), \(copy.detail)")
    }
}

// Codex's native dark avatar palette, selected by its raw thread-ID hash in Core.
// Keep the provider badge fixed; only the complete child activity line scrolls.
@MainActor
enum IslandSubagentAvatarImages {
    private static var images: [Int: NSImage] = [:]
    static func image(for avatar: CodexActivitySubagentAvatar) -> NSImage? {
        if let image = images[avatar.paletteIndex] { return image }
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: avatar.assetName, withExtension: "png", subdirectory: "CodexAgentAvatars"),
              let image = NSImage(contentsOf: url) else { return nil }
        images[avatar.paletteIndex] = image
        return image
    }
}

struct IslandSubagentStrip: View {
    @Environment(\.appLanguage) private var appLanguage
    let children: [IslandSubagentPresentation]
    let english: Bool
    let visible: Bool
    let reduceMotion: Bool
    private var copy: AppCopy { .init(language: appLanguage ?? (english ? .english : .simplifiedChinese)) }
    static func activityText(_ children: [IslandSubagentPresentation]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let font = NSFont.systemFont(ofSize: 11)
        func append(_ text: String, color: NSColor = IslandTextPalette.muted, weight: NSFont.Weight = .regular) {
            result.append(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: weight), .foregroundColor: color]))
        }
        func spacer(_ width: CGFloat, image: NSImage? = nil) {
            let space = "\u{2003}"
            let advance = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(
                NSAttributedString(string: space, attributes: [.font: font])), nil, nil, nil)
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: width - CGFloat(advance)]
            if let image { attributes[.islandInlineImage] = image }
            result.append(NSAttributedString(string: space, attributes: attributes))
        }
        for (index, child) in children.enumerated() {
            if index > 0 { spacer(24) }
            if let avatar = child.avatar, let image = IslandSubagentAvatarImages.image(for: avatar) {
                spacer(14, image: image)
                append(" ")
            }
            append(child.title, color: IslandTextPalette.detail, weight: .medium)
            if !child.model.isEmpty { append(" (" + child.model + ")") }
            append(" " + child.status)
            if !child.duration.isEmpty { append(" · " + child.duration) }
        }
        if result.length == 0 { return NSAttributedString(string: "", attributes: [.font: font]) }
        return result
    }
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                IslandTaskProviderIcon(provider: children.first?.provider ?? .codex, size: 14)
                    .accessibilityHidden(true)
                (Text(copy.islandSubagentGroupName(children.first?.provider ?? .codex) + " (") + Text("\(children.count)").foregroundColor(.white) + Text(")"))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(IslandBoardStyle.muted)
            }.fixedSize(horizontal: true, vertical: false)
            IslandAttributedScrollingText(text: Self.activityText(children), font: .systemFont(ofSize: 11),
                visible: visible, reduceMotion: reduceMotion, streamIdentity: children.map(\.id).joined(separator: "|"))
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }.frame(height: IslandVibeLayout.textRowHeight)
            .padding(.horizontal, IslandVibeLayout.contentInset)
            .frame(height: IslandVibeLayout.subagentRowHeight, alignment: .center)
            .help(children.map { [$0.title, $0.model, $0.status, $0.duration, $0.detail].filter { !$0.isEmpty }.joined(separator: " · ") }.joined(separator: "\n"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(copy.islandSubagentGroupTitle(count: children.count))
            .accessibilityValue(children.map { [$0.title, $0.model, $0.status, $0.duration].filter { !$0.isEmpty }.joined(separator: ", ") }.joined(separator: "; "))
    }
}

// One palette and material surface for the task and its child activity row.
struct IslandTaskCardAppearance {
    let visualState: CodexActivityVisualState
    let hovered: Bool
    var selected = false
    private var statusTint: NSColor { CodexActivityRippleGlowContract.statusTint(for: visualState) }
    var glassTint: Color {
        if selected || visualState == .completed {
            return .black.opacity(hovered ? 0.32 : 0.42)
        }
        let tint = NSColor.black.blended(withFraction: hovered ? 0.18 : 0.14, of: statusTint) ?? .black
        return Color(nsColor: tint).opacity(hovered ? 0.32 : 0.42)
    }
    var solidTint: Color {
        let base = NSColor(white: 0.055, alpha: 1)
        guard !selected, visualState != .completed else { return Color(nsColor: base) }
        return Color(nsColor: base.blended(withFraction: hovered ? 0.11 : 0.08, of: statusTint) ?? base)
    }
}

private enum IslandTaskHeaderAlignment: AlignmentID {
    static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[VerticalAlignment.center] }
}
extension VerticalAlignment {
    static let islandTaskHeader = VerticalAlignment(IslandTaskHeaderAlignment.self)
}

// Shared presentation: list rows add selection, approval headers are read-only.
struct IslandTaskCard: View {
    @Environment(\.appLanguage) private var appLanguage
    var progressEffect: AppPreferences.CodexActivityProgressEffect = .dropField
    var playsCompletionTransition = true
    @State private var completionPhase = IslandCardCompletionPhase.resting
    @State private var fillTimer: Task<Void, Never>?
    let task: CodexMultitaskRenderTask
    let selected: Bool
    let metadata: IslandSessionMetadata?
    let english: Bool
    let playback: Bool
    let effectVisible: Bool
    let reduceMotion: Bool
    var subagentsVisible = false
    var hovered = false
    var showsArchiveButton = false
    var cardWidth: CGFloat = 656
    // Settings can illustrate the same content on a taller surface without
    // stretching text, icons or the effect. Live cards retain their own height.
    var minimumCardHeight: CGFloat = 0
    private var appearance: IslandTaskCardAppearance {
        .init(visualState: task.renderState.visualState, hovered: hovered, selected: selected)
    }
    private var primaryContentHeight: CGFloat {
        max(minimumCardHeight, metadata?.primaryContentHeight(width: cardWidth) ?? IslandVibeLayout.rowHeight)
    }
    private var completionInput: IslandCardCompletionInput {
        .init(id: task.id, identity: task.renderState.taskIdentity, state: task.renderState.visualState,
              visible: playsCompletionTransition && effectVisible)
    }

    var body: some View {
        cardSurface
            .overlay {
                if completionPhase == .wave {
                    IslandCardCompletionWave(content: cardSurface, reduceMotion: reduceMotion) {
                        if completionPhase == .wave { completionPhase = .revealed(riseStart: CACurrentMediaTime()) }
                    }
                    .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .onChange(of: completionInput) { previous, current in
                fillTimer?.cancel()
                fillTimer = nil
                guard current.startsCompletion(after: previous) else {
                    completionPhase = .resting
                    return
                }
                if selected && !reduceMotion {
                    completionPhase = .filling
                    fillTimer = Task { @MainActor in
                        do { try await Task.sleep(for: .seconds(Double(CodexActivityStateSmokeContract.completionFillDuration))) }
                        catch { return }
                        completionPhase = .wave
                    }
                } else {
                    completionPhase = .wave
                }
            }
            .onDisappear {
                fillTimer?.cancel()
                fillTimer = nil
                completionPhase = .resting
            }
    }

    private var cardSurface: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: IslandVibeLayout.lineGap) {
                HStack(spacing: IslandVibeLayout.contentGap) {
                    // The selected card uses the progress effect instead of an orb.
                    // Remove its icon column too, as required by the task card layout.
                    if !selected && task.renderState.visualState != .completed {
                        IslandActivityOrb(visualState: task.renderState.visualState, playback: playback)
                            .frame(width: IslandVibeLayout.orbDiameter, height: IslandVibeLayout.orbDiameter)
                            .frame(width: IslandVibeLayout.iconSlot).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: IslandVibeLayout.lineGap) {
                        HStack(spacing: 6) {
                            if task.renderState.visualState == .completed {
                                IslandActivityOrb(visualState: .completed, playback: playback, completionPhase: completionPhase)
                                    .frame(width: 18, height: 18).accessibilityHidden(true)
                            }
                            IslandScrollingText(text: task.title,
                                font: .systemFont(ofSize: IslandVibeLayout.titleFont, weight: .semibold),
                                color: .white, visible: effectVisible, reduceMotion: reduceMotion)
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).accessibilityHint(task.title)
                            if let metadata, !metadata.modelTitle.isEmpty, !metadata.usesExtraLine {
                                Text(metadata.modelTitle).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                    .accessibilityHint(metadata.fullModelTitle)
                                // Model titles already contain "·"; a hairline separates the duration group.
                                if task.cardOptions.duration {
                                    Rectangle().fill(Color(white: 0.24)).frame(width: 1, height: 9).accessibilityHidden(true)
                                }
                            }
                            if let metadata, task.cardOptions.duration {
                                Text(metadata.durationTitle).monospacedDigit().fixedSize()
                            }
                            if !showsArchiveButton {
                                if IslandProviderIcon.settingsMark(for: task.provider) != nil {
                                    IslandTaskProviderIcon(provider: task.provider)
                                } else { Text(task.provider.displayName).foregroundStyle(IslandBoardStyle.muted) }
                            }
                        }.frame(height: IslandVibeLayout.textRowHeight)
                            .padding(.trailing, showsArchiveButton ? 28 : 0)
                            .font(.system(size: IslandVibeLayout.metadataFont, weight: .semibold))
                            .foregroundStyle(IslandBoardStyle.muted)
                            .alignmentGuide(.islandTaskHeader) { $0[VerticalAlignment.center] }
                        HStack(spacing: 8) {
                            IslandOperationLine(renderState: task.renderState, visible: effectVisible, reduceMotion: reduceMotion)
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                .clipped()
                            // Reserve only visible statistics; details use the rest.
                            if task.outputRate != nil || task.cardOptions.tokens {
                                HStack(spacing: 3) {
                                    if let rate = task.outputRate {
                                        HStack(spacing: 3) {
                                            Image(systemName: rate.symbolName).accessibilityHidden(true)
                                            Text(rate.title)
                                        }
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(AppCopy(language: appLanguage ?? (english ? .english : .simplifiedChinese)).text("输出速率", "Output rate") + " " + rate.title)
                                        if task.cardOptions.tokens {
                                            Rectangle().fill(Color(white: 0.24)).frame(width: 1, height: 9).accessibilityHidden(true)
                                        }
                                    }
                                    if task.cardOptions.tokens {
                                        Text(task.renderState.tokenUsageTitle ?? "— tok")
                                            .accessibilityHint(AppCopy(language: appLanguage ?? (english ? .english : .simplifiedChinese)).text("会话累计", "Session total"))
                                    }
                                }
                                .font(.system(size: IslandVibeLayout.metadataFont, weight: .medium)).monospacedDigit()
                                .foregroundStyle(IslandBoardStyle.muted)
                                .fixedSize(horizontal: true, vertical: false).layoutPriority(1)
                                .padding(.trailing, showsArchiveButton ? IslandVibeLayout.taskActionOpticalInset : 0)
                            }
                        }.frame(height: IslandVibeLayout.textRowHeight)
                    }
                }.frame(height: IslandVibeLayout.rowHeight - IslandVibeLayout.contentInset * 2)
                if let metadata, metadata.usesExtraLine {
                    Text(metadata.modelTitle).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(IslandBoardStyle.muted).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).accessibilityHint(metadata.fullModelTitle)
                }
            }.frame(width: max(0, cardWidth - IslandVibeLayout.contentInset * 2))
                .padding(IslandVibeLayout.contentInset).frame(height: primaryContentHeight)
            if let metadata, !metadata.subagents.isEmpty {
                IslandSubagentStrip(children: metadata.subagents, english: english,
                    visible: subagentsVisible, reduceMotion: reduceMotion)
            }
        }.frame(width: cardWidth)
            .background {
                if selected && completionPhase != .wave {
                    IslandQuantumProgress(effect: progressEffect, renderState: task.renderState, visible: effectVisible,
                        reduceMotion: reduceMotion, defersCompletionSkin: completionPhase == .filling,
                        completionRiseStart: completionPhase.riseStart, primaryContentHeight: primaryContentHeight)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .islandGlass(IslandVibeLayout.rowShape, tint: appearance.glassTint, solidTint: appearance.solidTint)
            .contentShape(IslandVibeLayout.rowShape)
            .accessibilityHint("\(task.title) · \(task.renderState.statusTitle)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(task.title), \(task.renderState.statusTitle), \(task.renderState.operation), \(metadata?.modelTitle ?? ""), \(task.cardOptions.duration ? metadata?.durationTitle ?? "" : ""), \(task.cardOptions.tokens ? task.renderState.tokenUsageTitle ?? "—" : ""), \(task.outputRate?.title ?? ""), \(metadata?.subagents.map { $0.title + ", " + $0.status }.joined(separator: "; ") ?? "")")
    }
}

struct IslandTaskArchiveButton: View {
    @Environment(\.appLanguage) private var appLanguage
    let english: Bool
    var showsArchiveIcon = true
    var provider: IslandAgentProvider = .codex
    let action: () -> Void
    @State private var hovered = false
    private var copy: AppCopy { .init(language: appLanguage ?? (english ? .english : .simplifiedChinese)) }
    var body: some View {
        Button(action: action) {
            Group {
                if showsArchiveIcon || IslandProviderIcon.settingsMark(for: provider) == nil {
                    Image("IslandTaskClear")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.white.opacity(hovered ? 1 : 0.55))
                } else {
                    IslandTaskProviderIcon(provider: provider).accessibilityHidden(true)
                }
            }.frame(width: IslandVibeLayout.taskActionSize, height: IslandVibeLayout.taskActionSize).contentShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(IslandArchiveButtonStyle(hovered: hovered))
            .onHover { hovered = $0 }
            .accessibilityLabel(copy.islandArchiveTask)
            .accessibilityHint(copy.islandArchiveTaskHint)
    }
}
private struct IslandArchiveButtonStyle: ButtonStyle {
    let hovered: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
            .brightness(configuration.isPressed ? -0.08 : hovered ? 0.06 : 0)
    }
}
