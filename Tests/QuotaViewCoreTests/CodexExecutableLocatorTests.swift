import Foundation
import XCTest
@testable import QuotaViewCore

final class CodexExecutableLocatorTests: XCTestCase {
    private let bundledCLI = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
    private let legacyCLI = "/Applications/ChatGPT.app/Contents/Resources/codex"

    func testDesktopLaunchFindsNestedCLIWithoutShellPath() {
        for appName in ["ChatGPT", "Codex"] {
            let path = "/Applications/\(appName).app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
            XCTAssertEqual(locate([path], environment: ["PATH": "/usr/bin:/bin"]), path)
        }
    }

    func testExecutableOverrideStillTakesPriority() {
        let override = "/custom/codex"
        XCTAssertEqual(locate([bundledCLI, override], environment: ["CODEX_EXECUTABLE": override]), override)
        XCTAssertEqual(locate([bundledCLI], environment: ["CODEX_EXECUTABLE": "/missing/codex"]), bundledCLI)
    }

    func testNewBundleTakesPriorityAndLegacyRemainsAvailable() {
        XCTAssertEqual(locate([bundledCLI, legacyCLI]), bundledCLI)
        for appName in ["ChatGPT", "Codex"] {
            let path = "/Applications/\(appName).app/Contents/Resources/codex"
            XCTAssertEqual(locate([path]), path)
        }
    }

    func testStandaloneCLIAndPathRemainAvailable() {
        for path in ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"] {
            XCTAssertEqual(locate([path]), path)
        }
        XCTAssertEqual(locate(["/custom/bin/codex"], environment: ["PATH": "/missing:/custom/bin"]), "/custom/bin/codex")
    }

    func testMissingOrNonExecutableCLIIsUnavailable() {
        XCTAssertNil(locate([], environment: ["CODEX_EXECUTABLE": bundledCLI, "PATH": "/missing"]))
    }

    private func locate(_ executablePaths: Set<String>, environment: [String: String] = [:]) -> String? {
        CodexExecutableLocator.locate(
            environment: environment,
            fileManager: ExecutableFileManager(executablePaths)
        )
    }
}

private final class ExecutableFileManager: FileManager, @unchecked Sendable {
    private let executablePaths: Set<String>

    init(_ executablePaths: Set<String>) {
        self.executablePaths = executablePaths
        super.init()
    }

    override func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }
}
