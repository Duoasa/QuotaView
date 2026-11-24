#!/bin/zsh
# Local opt-in launcher for Codex's shared App Server. No app/config patching.
set -eu
APP_PATH='/Applications/ChatGPT.app'
CLI_PATH="$APP_PATH/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
if [[ ! -x "$CLI_PATH" ]]; then
  print -u2 '找不到已验证的 Codex 安装，请重新检查应用路径。'
  exit 1
fi
if /bin/ps -axo comm= | /usr/bin/grep -Fxq "$APP_PATH/Contents/MacOS/ChatGPT"; then
  print -u2 '请先保存工作并完全退出 Codex，再重新运行此文件。脚本不会关闭正在运行的会话。'
  exit 1
fi
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")
if [[ "$BUNDLE_ID" != 'com.openai.codex' ]]; then
  print -u2 '应用身份不匹配，未启动。'
  exit 1
fi
# Starts/reuses the native service in the existing Codex data directory.
# Never restart/stop an existing daemon: other clients may be using it.
"$CLI_PATH" app-server daemon start
"$CLI_PATH" app-server daemon version
# This launch only. Normal launches remain unchanged; no launchctl/config edits.
/usr/bin/open -a "$APP_PATH" --env CODEX_APP_SERVER_USE_LOCAL_DAEMON=1
print '已请求以共享回答通道启动 Codex。请在新的测试问题中验证灵动岛作答。'
