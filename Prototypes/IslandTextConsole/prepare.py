#!/usr/bin/env python3
"""Prepare an isolated DEBUG console from the current production renderer."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
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

# Resolve declarations before adding the console's own Swift sources.
def source_declaring(pattern):
    matches = [path for path in app.rglob('*.swift')
               if re.search(pattern, path.read_text(), re.MULTILINE)]
    if len(matches) != 1:
        raise ValueError(f'Expected one source declaring {pattern!r}, found {matches}')
    return matches[0]


entry = source_declaring(r'^@main$')
renderer = source_declaring(r'^final class ActivityIslandContentView\b')
effect = source_declaring(r'^final class ActivityStateSmokeMetalView\b')
# The console supplies its own @main. Keep the production types for their callers.
entry.write_text(re.sub(r'^@main\n', '', entry.read_text(), count=1, flags=re.MULTILINE))
shutil.copy2(console / 'ConsoleApp.swift', app / 'ConsoleApp.swift')
shutil.copy2(console / 'ConsoleMotion.swift', app / 'ConsoleMotion.swift')
shutil.copy2(console / 'tests/RendererTextLayoutTests.swift',
             stage / 'Tests/QuotaViewCoreTests/RendererTextLayoutTests.swift')

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

entry_relative = entry.relative_to(stage).as_posix()
production_files = {}
for path in sorted((root / 'Sources').rglob('*')):
    if not path.is_file():
        continue
    relative = path.relative_to(root).as_posix()
    production_files[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    if relative != entry_relative:
        assert (stage / relative).read_bytes() == path.read_bytes(), relative
renderer_relative = renderer.relative_to(stage).as_posix()
(console / '.build' / 'source-manifest.json').write_text(json.dumps({
    'source': str(root / renderer_relative),
    'sha256': production_files[renderer_relative],
    'rendererChanges': 'none',
    'hostAdapters': [entry_relative],
    'effectSource': effect.relative_to(stage).as_posix(),
    'productionFiles': production_files,
    'consoleFiles': {name: hashlib.sha256((console / name).read_bytes()).hexdigest()
                     for name in ['ConsoleApp.swift', 'ConsoleMotion.swift', 'prepare.py', 'build.sh',
                                  'tests/RendererTextLayoutTests.swift']},
    'data': 'DEBUG fixtures only; no production delegate, stores, bridge, widgets or updater'
}, indent=2))
