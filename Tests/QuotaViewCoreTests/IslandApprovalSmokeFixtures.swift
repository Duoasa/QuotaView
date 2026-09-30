import Foundation
@testable import QuotaView

enum IslandApprovalFixtures {
    static let names: [(String, IslandDetailText)] = [
        ("command", .init("命令批准", "Command")),
        ("terminalInput", .init("终端输入", "Terminal input")),
        ("fileChange", .init("文件修改", "File changes")),
        ("network", .init("网络访问", "Network access")),
        ("permissions", .init("权限范围", "Permissions")),
        ("connector", .init("第三方操作", "Connector action")),
        ("questions", .init("问题选择", "Questions")),
        ("mcpForm", .init("工具表单", "MCP form")),
        ("mcpURL", .init("外部授权", "External authorization")),
        ("nativeOnly", .init("原生验证", "Native verification"))
    ]
    static func taskTitle(_ name: String, english: Bool) -> String {
        let title: IslandDetailText
        switch name {
        case "command": title = .init("QuotaView · 编译开发台", "QuotaView · Build the console")
        case "terminalInput": title = .init("Widget · 继续迁移流程", "Widget · Continue migration")
        case "fileChange": title = .init("QuotaView · 更新运行配置", "QuotaView · Update configuration")
        case "network": title = .init("QuotaView · 获取版本信息", "QuotaView · Fetch release metadata")
        case "permissions": title = .init("Widget · 导入历史记录", "Widget · Import history")
        case "connector": title = .init("文档 · 更新项目说明", "Docs · Update project notes")
        case "questions": title = .init("QuotaView · 确认修改范围", "QuotaView · Choose the scope")
        case "mcpForm": title = .init("文档 · 导出验收报告", "Docs · Export the report")
        case "mcpURL": title = .init("工具 · 连接外部服务", "Tools · Connect a provider")
        default: title = .init("工具 · 完成身份验证", "Tools · Verify identity")
        }
        return title.value(english)
    }
    static func request(_ name: String) throws -> IslandCodexApprovalRequest {
        var method = "item/commandExecution/requestApproval"
        var params: [String: IslandApprovalJSON] = [
            "threadId": .string("debug-thread-\(name)"), "turnId": .string("debug-turn"),
            "itemId": .string("debug-item-\(name)")
        ]
        switch name {
        case "terminalInput":
            params["kind"] = .string("writeStdin")
            params["approvalId"] = .string("debug-stdin-callback")
            params["command"] = .string("y\n")
            params["reason"] = .string("迁移程序正在等待输入；发送 y 和换行后继续。此为模拟终端，不执行真实迁移。")
            params["availableDecisions"] = .array([.string("decline"), .string("accept"), .string("cancel")])
        case "fileChange":
            method = "item/fileChange/requestApproval"
            params["reason"] = .string("应用以下配置修改，保留原有记录。请先检查文件差异。")
            params["grantRoot"] = .string("/tmp/quotaview-approval-demo")
        case "network":
            params["networkApprovalContext"] = .object(["host": .string("api.example.com"), "protocol": .string("https")])
            params["reason"] = .string("获取版本元数据。此请求需要沙盒外的网络访问。")
            params["proposedNetworkPolicyAmendments"] = .array([
                .object(["host": .string("api.example.com"), "action": .string("allow")]),
                .object(["host": .string("api.example.com"), "action": .string("deny")])
            ])
        case "permissions":
            method = "item/permissions/requestApproval"
            params["cwd"] = .string("/tmp/quotaview-approval-demo")
            params["reason"] = .string("读取历史记录并导出到新目录。你可以只授予需要的权限。")
            params["permissions"] = .object([
                "network": .object(["enabled": .bool(true)]),
                "fileSystem": .object(["read": .array([.string("/tmp/demo-input")]),
                                      "write": .array([.string("/tmp/demo-output")])])
            ])
        case "questions", "connector":
            method = "item/tool/requestUserInput"
            params["isBlocking"] = .bool(name == "connector"); params["autoResolutionMs"] = .null
            params["questions"] = name == "connector" ? .array([
                .object(["id": .string("approve-tool"), "header": .string("Approval"),
                         "question": .string("是否允许更新选中的项目说明文档？"),
                         "isOther": .bool(false), "isSecret": .bool(false),
                         "options": .array(["Accept", "Decline", "Cancel"].map {
                            .object(["label": .string($0), "description": .string($0 == "Accept" ? "执行本次文档更新" : $0 == "Decline" ? "拒绝这次工具调用" : "取消当前请求")])
                         })])
            ]) : .array([
                .object(["id": .string("scope"), "header": .string("Scope"),
                         "question": .string("这次修改应覆盖哪些文件？"),
                         "isOther": .bool(true), "isSecret": .bool(false),
                         "options": .array([
                            .object(["label": .string("Current module"), "description": .string("只修改当前模块，范围更小")]),
                            .object(["label": .string("Whole project"), "description": .string("同步调整项目内的关联模块")])
                         ])]),
                .object(["id": .string("note"), "header": .string("Constraints"),
                         "question": .string("还有哪些需要保留的行为或限制？"),
                         "isOther": .bool(true), "isSecret": .bool(false), "options": .null])
            ])
        case "mcpForm":
            method = "mcpServer/elicitation/request"
            params["serverName"] = .string("demo-server"); params["mode"] = .string("form")
            params["message"] = .string("填写导出参数后，工具将继续生成报告。")
            params["requestedSchema"] = .object([
                "type": .string("object"), "required": .array([.string("format"), .string("copies"), .string("includeNotes")]),
                "properties": .object([
                    "format": .object(["type": .string("string"), "title": .string("导出格式"),
                                      "oneOf": .array([
                                        .object(["const": .string("Markdown"), "title": .string("Markdown · 文档")]),
                                        .object(["const": .string("PDF"), "title": .string("PDF · 打印版")])
                                      ])]),
                    "copies": .object(["type": .string("integer"), "title": .string("份数"), "description": .string("1–10"), "minimum": .number(1), "maximum": .number(10)]),
                    "includeNotes": .object(["type": .string("boolean"), "title": .string("附带说明")]),
                    "tags": .object(["type": .string("array"), "title": .string("文档标签"),
                                    "items": .object(["anyOf": .array([
                                        .object(["const": .string("review"), "title": .string("待审阅")]),
                                        .object(["const": .string("archive"), "title": .string("归档")])
                                    ])])]),
                    "note": .object(["type": .string("string"), "title": .string("补充备注"), "description": .string("可选，最多 120 字"), "maxLength": .number(120)])
                ])
            ])
        case "mcpURL":
            method = "mcpServer/elicitation/request"
            params["serverName"] = .string("demo-server"); params["mode"] = .string("url")
            params["url"] = .string("https://example.com/authorize")
            params["elicitationId"] = .string("debug-authorization")
            params["message"] = .string("该工具需要服务商授权。Island 只演示打开和返回两步，不访问真实网址。")
        case "nativeOnly":
            method = "mcpServer/elicitation/request"
            params["serverName"] = .string("demo-server"); params["mode"] = .string("openai/userVerification")
            params["description"] = .string("该请求需要 Codex 原生验证界面。灵动岛提供跳回入口，不能代替身份验证；此处仅模拟跳转。")
        default:
            params["kind"] = .string("command")
            params["command"] = .string("swift build --package-path Prototypes/MultitaskIslandIsland/.build/Workspace --product QuotaView")
            params["cwd"] = .string("~/Documents/widget/.worktrees/QuotaView-0.4.8")
            params["reason"] = .string("构建需要写入工作区外的 Swift 缓存目录。允许后继续当前构建步骤。")
            params["proposedExecpolicyAmendment"] = .array([.string("swift"), .string("build")])
        }
        let envelope = IslandApprovalJSON.object(["id": .string("debug-request-\(name)"), "method": .string(method), "params": .object(params)])
        var request = try IslandCodexApprovalRequest(data: envelope.data)
        if name == "fileChange" {
            request.contextItem = .object(["type": .string("fileChange"), "changes": .array([
                .object(["path": .string("/tmp/quotaview-approval-demo/config.json"),
                         "diff": .string("@@ -1,4 +1,4 @@\n {\n-  \"theme\": \"auto\",\n+  \"theme\": \"dark\",\n   \"preserveHistory\": true\n }")]),
                .object(["path": .string("/tmp/quotaview-approval-demo/README.md"),
                         "diff": .string("@@ -2,2 +2,3 @@\n ## 使用说明\n+开发台采用深色模式，保留历史记录。")])
            ])])
        } else if name == "connector" {
            request.contextItem = .object(["type": .string("mcpToolCall"), "server": .string("项目文档"),
                "tool": .string("update_page"), "arguments": .object([
                    "page_id": .string("project-notes"),
                    "title": .string("QuotaView · 开发台交接"),
                    "content": .string("更新本轮 UI Island 的展示范围与已知限制。")
                ])])
        }
        return request
    }
    static func confirmation(_ name: String) throws -> IslandConfirmation {
        let request = try request(name)
        return .init(question: request.kind.title,
            impact: .init([request.detail, request.context].filter { !$0.isEmpty }.joined(separator: "\n")),
            resumeOperation: .init("继续模拟任务", "Continue simulated task"), protocolRequest: request)
    }
}
