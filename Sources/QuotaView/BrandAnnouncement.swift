import AppKit
import SwiftUI

/// An explicit release list keeps a preview from becoming a public announcement.
struct BrandAnnouncementCampaign {
    let id: String
    let releaseBuilds: Set<String>

    // Configure the two exact release build IDs after the announcement is accepted.
    static let current = Self(id: "brand-refresh-2026", releaseBuilds: [])
    var storageKey: String { "announcement.\(id).acknowledgedBuilds" }

    func shouldPresent(build: String, acknowledged: Set<String>) -> Bool {
        releaseBuilds.contains(build) && !acknowledged.contains(build)
    }

    func acknowledging(build: String, in acknowledged: Set<String>) -> Set<String> {
        guard releaseBuilds.contains(build) else { return acknowledged }
        return acknowledged.union([build])
    }
}

@MainActor
final class BrandAnnouncementController: NSObject, NSWindowDelegate {
    static let shared = BrandAnnouncementController()
    private var controller: NSWindowController?
    private var acknowledge: (() -> Void)?

    static var isAvailable: Bool {
        #if DEBUG
        if Bundle.main.bundleIdentifier == "com.quotaview.development073" { return true }
        #endif
        return !BrandAnnouncementCampaign.current.releaseBuilds.isEmpty
    }

    func presentOnLaunch(copy: AppCopy, bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        #if DEBUG
        if bundle.bundleIdentifier == "com.quotaview.development073",
           ProcessInfo.processInfo.arguments.contains("--preview-brand-announcement") {
            showPreview(copy: copy)
            return
        }
        #endif
        let campaign = BrandAnnouncementCampaign.current
        guard bundle.bundleIdentifier == "com.quotaview.menubar",
              let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              campaign.shouldPresent(build: build, acknowledged: Set(defaults.stringArray(forKey: campaign.storageKey) ?? []))
        else { return }
        present(copy: copy, preview: false) {
            let seen = Set(defaults.stringArray(forKey: campaign.storageKey) ?? [])
            defaults.set(campaign.acknowledging(build: build, in: seen).sorted(), forKey: campaign.storageKey)
        }
    }

    func showPreview(copy: AppCopy) {
        // Manual viewing never consumes either release's first-launch reminder.
        present(copy: copy, preview: BrandAnnouncementCampaign.current.releaseBuilds.isEmpty, onDismiss: nil)
    }

    private func present(copy: AppCopy, preview: Bool, onDismiss: (() -> Void)?) {
        if let window = controller?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        acknowledge = onDismiss
        let content = BrandAnnouncementView(copy: copy, preview: preview) { [weak self] in
            self?.controller?.window?.performClose(nil)
        }
        let window = BrandAnnouncementWindow(contentViewController: NSHostingController(rootView: content))
        window.title = copy.text("QuotaView 品牌升级预告", "QuotaView brand announcement")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self
        SettingsWindowMetrics.applyOuterShape(to: window)
        window.setContentSize(NSSize(width: 520, height: 520))
        window.center()
        controller = NSWindowController(window: window)
        controller?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        let action = acknowledge
        acknowledge = nil
        controller = nil
        action?()
    }
}

private final class BrandAnnouncementWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

private struct BrandAnnouncementView: View {
    let copy: AppCopy
    let preview: Bool
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if preview {
                    Text(copy.text("预览", "Preview"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }.frame(height: 28).padding(.horizontal, 24).padding(.top, 10)

            ZStack {
                Circle()
                    .fill(Color(red: 0.43, green: 0.54, blue: 0.86).opacity(0.16))
                    .frame(width: 140, height: 140).blur(radius: 32)
                Image(nsImage: SettingsFeedbackResources.appIcon)
                    .resizable().scaledToFit().frame(width: 104, height: 104)
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                    .accessibilityHidden(true)
            }.frame(height: 148)

            Text(copy.text("品牌升级预告", "A NEW LOOK IS COMING"))
                .font(.system(size: 11, weight: .medium)).tracking(2)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Text(copy.text("熟悉的 QuotaView\n即将焕新", "The QuotaView you know.\nA fresh look ahead."))
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.5).lineSpacing(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            Text(copy.text(
                "我们正在为 QuotaView 准备新的品牌形象。\n继续照常使用，后续进展会在应用内告知。",
                "We're preparing a new visual identity for QuotaView.\nKeep using the app as usual. More details will follow here."))
                .font(.system(size: 13)).lineSpacing(5)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
            Spacer(minLength: 24)
            Button(action: dismiss) {
                Text(copy.text("继续使用", "Continue"))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(BrandAnnouncementButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 76).padding(.bottom, 32)
        }
        .frame(width: 520, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark)
        .onExitCommand(perform: dismiss)
    }
}

private struct BrandAnnouncementButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.black.opacity(0.88))
            .background(Color.white.opacity(configuration.isPressed ? 0.72 : 0.94),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
