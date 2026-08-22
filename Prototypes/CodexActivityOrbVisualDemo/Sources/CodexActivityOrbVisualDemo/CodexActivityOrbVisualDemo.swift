import AppKit
import CoreText
import Darwin
import SwiftUI

private enum DemoFontRegistrar {
    static func register() {
        var repositoryRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            repositoryRoot.deleteLastPathComponent()
        }
        let fontsDirectory = repositoryRoot
            .appendingPathComponent("Resources/Fonts", isDirectory: true)
        for name in [
            "AstaSans-Regular.ttf",
            "AstaSans-Medium.ttf",
            "AstaSans-SemiBold.ttf"
        ] {
            let url = fontsDirectory.appendingPathComponent(name)
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

private final class DemoAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DemoFontRegistrar.register()
        let content = NSHostingView(rootView: OrbVisualDemoView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuotaView 单灵动岛状态 Demo"
        window.minSize = NSSize(width: 760, height: 680)
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        installMainMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "退出 AI 球 Demo",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}

// PROTOTYPE-ONLY: isolated visual demo entry point.
@main
private enum CodexActivityOrbVisualDemo {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--smoke-test") {
            do {
                let report = try MetalOrbSmokeTest.run()
                print("AI Orb smoke test: PASS")
                print("Metal device: \(report.deviceName)")
                print("Uniform bytes: \(report.uniformBytes)")
                print("Offscreen render: \(report.renderSize)x\(report.renderSize)")
                print("Rendered states: \(report.renderedStateCount)")
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(
                    Data("AI Orb smoke test: FAIL\n\(error.localizedDescription)\n".utf8)
                )
                exit(EXIT_FAILURE)
            }
        }

        let application = NSApplication.shared
        let delegate = DemoAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
