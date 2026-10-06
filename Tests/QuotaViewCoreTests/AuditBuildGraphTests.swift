import Foundation
import XCTest

/// Locks the native build graph to the package source/test inventory. These
/// assertions detect orphaned modules and missing membership before packaging.
final class AuditBuildGraphTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func graph() throws -> [String: [String: Any]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = ["-convert", "json", "-o", "-", root.appendingPathComponent("QuotaView.xcodeproj/project.pbxproj").path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(document["objects"] as? [String: [String: Any]])
    }

    private func paths(_ objects: [String: [String: Any]]) -> [String: String] {
        var result: [String: String] = [:]
        func walk(_ id: String, parent: String) {
            guard let object = objects[id] else { return }
            let component = object["path"] as? String ?? ""
            let path = component.isEmpty ? parent : (parent as NSString).appendingPathComponent(component)
            if let children = object["children"] as? [String] {
                for child in children { walk(child, parent: path) }
            } else if object["sourceTree"] as? String == "<group>" {
                result[id] = path
            }
        }
        walk("G10000000000000000000001", parent: "")
        return result
    }

    private func members(_ name: String, phaseType: String, objects: [String: [String: Any]]) throws -> Set<String> {
        let target = try XCTUnwrap(objects.values.first { $0["isa"] as? String == "PBXNativeTarget" && $0["name"] as? String == name })
        let pathMap = paths(objects)
        let phases = try XCTUnwrap(target["buildPhases"] as? [String])
        let phase = try XCTUnwrap(phases.compactMap { objects[$0] }.first { $0["isa"] as? String == phaseType })
        let files = try XCTUnwrap(phase["files"] as? [String])
        return Set(files.compactMap { id in
            guard let reference = objects[id]?["fileRef"] as? String else { return nil }
            return pathMap[reference]
        })
    }

    func testAllNativeModulesAndTestsHaveSourceMembership() throws {
        let objects = try graph()
        let targets = [
            ("QuotaView", "Sources/QuotaView"),
            ("QuotaViewCore", "Sources/QuotaViewCore"),
            ("QuotaViewFutureContracts", "Sources/QuotaViewFutureContracts"),
            ("QuotaViewActivityHookSupport", "Sources/QuotaViewActivityHookSupport"),
            ("QuotaViewWidgetContract", "Sources/QuotaViewWidgetContract"),
            ("QuotaViewTests", "Tests/QuotaViewCoreTests")
        ]
        for (target, directory) in targets {
            let expected = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(directory).path)
                .filter { $0.hasSuffix(".swift") }.map { directory + "/" + $0 }
            let actual = try members(target, phaseType: "PBXSourcesBuildPhase", objects: objects)
            XCTAssertTrue(Set(expected).isSubset(of: actual), "\(target) is missing \(Set(expected).subtracting(actual).sorted())")
        }
        let support = try members("QuotaViewActivityHookSupport", phaseType: "PBXSourcesBuildPhase", objects: objects)
        let hook = try members("QuotaViewActivityHook", phaseType: "PBXSourcesBuildPhase", objects: objects)
        for file in ["PlanProgressParser.swift", "ActivityPrivacyRules.swift"] {
            XCTAssertTrue(support.contains("Sources/QuotaViewActivityHookSupport/" + file))
            XCTAssertTrue(hook.contains("Sources/QuotaViewActivityHookSupport/" + file))
        }
        XCTAssertTrue(try members("QuotaViewWidgetExtension", phaseType: "PBXSourcesBuildPhase", objects: objects).contains("Sources/QuotaViewWidget/QuotaViewWidget.swift"))
    }

    func testAppEmbedsCoreDependencies() throws {
        let objects = try graph()
        func target(_ name: String) throws -> [String: Any] {
            try XCTUnwrap(objects.values.first { $0["isa"] as? String == "PBXNativeTarget" && $0["name"] as? String == name })
        }
        func products(_ target: [String: Any], type: String, name: String? = nil) throws -> Set<String> {
            let phases = try XCTUnwrap(target["buildPhases"] as? [String])
            let phase = try XCTUnwrap(phases.compactMap { objects[$0] }.first {
                $0["isa"] as? String == type && (name == nil || $0["name"] as? String == name)
            })
            return Set(try XCTUnwrap(phase["files"] as? [String]).compactMap { file in
                guard let ref = objects[file]?["fileRef"] as? String else { return nil }
                return objects[ref]?["path"] as? String
            })
        }
        let app = try target("QuotaView")
        let embedded = try products(app, type: "PBXCopyFilesBuildPhase", name: "Embed Frameworks")
        for name in ["QuotaViewCore", "QuotaViewWidgetContract", "QuotaViewActivityHookSupport"] {
            XCTAssertTrue(embedded.contains(name + ".framework"), "App must embed " + name)
        }
        let core = try target("QuotaViewCore")
        XCTAssertTrue(try products(core, type: "PBXFrameworksBuildPhase").contains("QuotaViewActivityHookSupport.framework"))
        let dependencies = try XCTUnwrap(core["dependencies"] as? [String]).compactMap { dependency -> String? in
            guard let id = objects[dependency]?["target"] as? String else { return nil }
            return objects[id]?["name"] as? String
        }
        XCTAssertTrue(dependencies.contains("QuotaViewActivityHookSupport"))
    }

    func testHostedTestActionUsesItsOwnIsolationEnvironment() throws {
        let url = root.appendingPathComponent("QuotaView.xcodeproj/xcshareddata/xcschemes/QuotaView.xcscheme")
        let document = try XMLDocument(contentsOf: url)
        let action = try XCTUnwrap(document.rootElement()?.elements(forName: "TestAction").first)
        XCTAssertEqual(action.attribute(forName: "shouldUseLaunchSchemeArgsEnv")?.stringValue, "NO")
        let environment = try XCTUnwrap(action.elements(forName: "EnvironmentVariables").first)
        let variables = environment.elements(forName: "EnvironmentVariable")
        for (key, value) in [("QUOTAVIEW_DISABLE_RUNTIME_FOR_TESTS", "1"), ("CODEX_EXECUTABLE", "/nonexistent/QuotaViewTestCodex")] {
            let variable = try XCTUnwrap(variables.first { $0.attribute(forName: "key")?.stringValue == key })
            XCTAssertEqual(variable.attribute(forName: "value")?.stringValue, value)
            XCTAssertEqual(variable.attribute(forName: "isEnabled")?.stringValue, "YES")
        }
    }

    func testRequiredNativeResourcesHaveMembership() throws {
        let objects = try graph()
        let app = try members("QuotaView", phaseType: "PBXResourcesBuildPhase", objects: objects)
        for path in ["Resources/Fonts", "Resources/Assets.xcassets", "Sources/QuotaView/Resources/CodexProviderIcon.png", "Sources/QuotaView/Resources/CodexActivityRippleGlowShader.txt", "Sources/QuotaView/Resources/CodexAgentAvatars", "Sources/QuotaView/Resources/QuotaViewFeedbackQQ.jpg"] {
            XCTAssertTrue(app.contains(path), "Missing native resource: \(path)")
        }
        let widget = try members("QuotaViewWidgetExtension", phaseType: "PBXResourcesBuildPhase", objects: objects)
        XCTAssertTrue(widget.contains("Resources/Fonts"))
        XCTAssertTrue(widget.contains("Sources/QuotaViewWidget/WidgetAssets.xcassets"))
    }
}
