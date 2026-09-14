#!/usr/bin/env python3
"""Prepare an isolated DEBUG console from the current production renderer."""
from pathlib import Path
import hashlib
import json
import plistlib
import shutil

console = Path(__file__).resolve().parent
root = console.parent.parent
stage = console / '.build' / 'Workspace'
stage.mkdir(parents=True, exist_ok=True)
for directory in ['Sources', 'Tests']:
    if (stage / directory).exists():
        shutil.rmtree(stage / directory)
    shutil.copytree(root / directory, stage / directory)
for name in ['Package.swift', 'Package.resolved']:
    if (root / name).exists():
        shutil.copy2(root / name, stage / name)
    elif (stage / name).exists():
        (stage / name).unlink()
app = stage / 'Sources' / 'QuotaView'
entry = app / 'QuotaViewApp.swift'
text = entry.read_text()
start = text.index('@MainActor\nfinal class QuotaViewAppDelegate')
# Keep referenced types, but never instantiate the production app delegate.
entry.write_text('import AppKit\nimport SwiftUI\n\n' + text[start:])
shutil.copy2(console / 'ConsoleApp.swift', app / 'ConsoleApp.swift')
shutil.copy2(console / 'ConsoleMotion.swift', app / 'ConsoleMotion.swift')
island = app / 'CodexActivityIsland.swift'
source = island.read_text()
old = 'private final class ActivityIslandContentView:'
assert source.count(old) == 1
island.write_text(source.replace(old, 'final class ActivityIslandContentView:'))
shutil.copy2(console / 'tests/RendererTextLayoutTests.swift',
             stage / 'Tests/QuotaViewCoreTests/RendererTextLayoutTests.swift')
# The only renderer change in this workspace is visibility for the preview host.
assert island.read_text().replace('final class ActivityIslandContentView:', old) == source

version = plistlib.loads((root / 'Support/Info.plist').read_bytes())
info = {
    'CFBundleIdentifier': 'com.quotaview.island-text-console',
    'CFBundleName': 'Island Text Console',
    'CFBundleExecutable': 'IslandTextConsole',
    'CFBundlePackageType': 'APPL',
    'NSHighResolutionCapable': True,
    'LSMinimumSystemVersion': '14.0',
}
for key in ['CFBundleShortVersionString', 'CFBundleVersion', 'QuotaViewDisplayBuildNumber']:
    info[key] = version[key]
(console / '.build' / 'Console-Info.plist').write_bytes(plistlib.dumps(info))

# Resolve the bundled shader from standard macOS Resources in the standalone app.
ripple = app / 'CodexActivityRippleGlow.swift'
text = ripple.read_text()
old = '        let bundle = Bundle.module'
assert text.count(old) == 1
text = text.replace(old, '\n'.join([
    '        let bundle = Bundle.main.resourceURL',
    '            .flatMap { Bundle(url: $0.appendingPathComponent("QuotaView_QuotaView.bundle")) }',
    '            ?? Bundle.module'
]))
ripple.write_text(text)

# Record the complete current source, including LONG-020's shared Metal code and clocks.
# Apart from these three host adapters, every production file must be byte-identical.
adapters = {'Sources/QuotaView/QuotaViewApp.swift', 'Sources/QuotaView/CodexActivityIsland.swift',
            'Sources/QuotaView/CodexActivityRippleGlow.swift'}
production_files = {}
for path in sorted((root / 'Sources').rglob('*')):
    if not path.is_file():
        continue
    relative = path.relative_to(root).as_posix()
    production_files[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    if relative not in adapters:
        assert (stage / relative).read_bytes() == path.read_bytes(), relative
(console / '.build' / 'source-manifest.json').write_text(json.dumps({
    'source': str(root / 'Sources/QuotaView/CodexActivityIsland.swift'),
    'sha256': hashlib.sha256(source.encode()).hexdigest(),
    'rendererChanges': 'ActivityIslandContentView visibility only',
    'hostAdapters': sorted(adapters),
    'effectSource': 'Sources/QuotaView/CodexActivityStateSmoke.swift',
    'productionFiles': production_files,
    'consoleFiles': {name: hashlib.sha256((console / name).read_bytes()).hexdigest()
                     for name in ['ConsoleApp.swift', 'ConsoleMotion.swift', 'prepare.py', 'build.sh',
                                  'tests/RendererTextLayoutTests.swift']},
    'data': 'DEBUG fixtures only; no production delegate, stores, bridge, widgets or updater'
}, indent=2))
