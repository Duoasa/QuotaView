#!/usr/bin/env python3
"""Exercise only synthetic sealing/appcast fixtures; never package or use keys."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
assert (ROOT / 'scripts/build-app.sh').is_file(), 'Run the committed Tests/BuildScripts fixture from a repository'
LOG = ROOT / '.build/audit-20261006/C'
LOG.mkdir(parents=True, exist_ok=True)
RESULTS = {}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def tree(path):
    return {p.relative_to(path).as_posix(): sha(p) for p in path.rglob('*') if p.is_file()}

def tool(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    path.chmod(0o755)

def execute(name, command, env):
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=30)
    (LOG / (name + '.log')).write_text(result.stdout + result.stderr)
    RESULTS[name] = result.returncode
    print(name, 'exit', result.returncode)
    return result.returncode

def info(app, widget=False):
    data = plistlib.loads((ROOT / 'Support/Info.plist').read_bytes())
    data['CFBundleIdentifier'] = 'com.quotaview.menubar' + ('.widget' if widget else '')
    data['QuotaViewAppGroupIdentifier'] = 'BUUH229D5Q.com.quotaview.shared'
    data['SURequireSignedFeed'] = True
    data['SUVerifyUpdateBeforeExtraction'] = True
    p = app / 'Contents/Info.plist'
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(plistlib.dumps(data))
    return data

seal = (ROOT / 'scripts/build-app.sh').read_text().split('# AUDIT-027: BEGIN SEAL\n')[1].split('# AUDIT-027: END SEAL')[0]
with tempfile.TemporaryDirectory(prefix='qv-release-synthetic-') as temporary:
    fixture_root = Path(temporary).resolve()
    # All mutable paths must be inside this new temporary root.
    def seal_fixture(label, mode='success', legacy=False, unit=False):
        base = fixture_root / label
        dist, staging = base / 'dist', base / 'staging'
        dist.mkdir(parents=True); staging.mkdir()
        name = 'QuotaView-v0.0.0-build.1'
        app, archive = staging / 'QuotaView.app', staging / (name + '.zip')
        info(app); info(app / 'Contents/PlugIns/QuotaViewWidgetExtension.appex', True)
        (app / 'Contents/payload').write_bytes(b'NEW_APP_SYNTHETIC')
        archive.write_bytes(b'NEW_ZIP_SYNTHETIC')
        if legacy:
            old_app = dist / 'QuotaView.app/Contents'
            old_app.mkdir(parents=True)
            (old_app / 'payload').write_bytes(b'OLD_APP_SEALED_SENTINEL')
            (dist / (name + '.zip')).write_bytes(b'OLD_ZIP_SEALED_SENTINEL')
            (dist / (name + '.manifest.json')).write_bytes(b'OLD_MANIFEST_SEALED_SENTINEL')
        if unit:
            old_unit = dist / name
            old_unit.mkdir()
            (old_unit / 'QuotaView.app').mkdir()
            (old_unit / 'QuotaView.app/payload').write_bytes(b'OLD_APP_SEALED_SENTINEL')
            (old_unit / (name + '.zip')).write_bytes(b'OLD_ZIP_SEALED_SENTINEL')
            (old_unit / (name + '.manifest.json')).write_text('{}')
        derived = staging / 'DerivedData'
        artifacts = derived / 'SourcePackages/artifacts'
        artifacts.mkdir(parents=True)
        project = base / 'source'
        project.mkdir()
        source = project / 'build-input.swift'
        source.write_text('let capturedInput = 1\n')
        subprocess.run(['git', 'init', '-q', '--template=', str(project)], check=True, capture_output=True)
        subprocess.run(['git', '-C', str(project), 'add', 'build-input.swift'], check=True, capture_output=True)
        commit_command = ['git', '-C', str(project), '-c', 'user.name=Synthetic Release Test',
                          '-c', 'user.email=audit@invalid.test', '-c', 'commit.gpgsign=false',
                          '-c', 'core.hooksPath=/dev/null', 'commit', '-q', '-m', 'Synthetic input']
        subprocess.run(commit_command, check=True, capture_output=True)
        identity_file = staging / 'source-identity.json'
        subprocess.run(['python3', str(ROOT / 'scripts/release-source-identity.py'), 'capture',
                        str(project), str(identity_file)], check=True, capture_output=True)
        signer = artifacts / 'mock/Sparkle/bin/sign_update'
        if mode != 'missing':
            tool(signer, '#!/bin/zsh\n' + ('exit 41\n' if mode == 'sign-failure' else 'if [[ "$*" == *--verify* ]]; then\n' + ('exit 42\n' if mode == 'verify-failure' else 'exit 0\n') + 'fi\nprint SYNTHETIC_SIGNATURE\n'))
        env = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'staging_app': str(app),
               'staging_zip': str(archive), 'staging_zip_sha256': sha(archive),
               'destination_release': str(dist / name), 'destination_zip': str(dist / name / (name + '.zip')),
               'release_name': name, 'derived_data': str(derived), 'project_dir': str(project),
               'script_dir': str(ROOT / 'scripts'), 'source_identity_file': str(identity_file),
               'sparkle_key_account': 'SYNTHETIC_NO_KEYCHAIN', 'is_developer_id': 'true',
               'notary_profile': 'SYNTHETIC_NO_KEYCHAIN', 'signing_identity': 'SYNTHETIC_SIGNER'}
        assert all(Path(env[key]).resolve().is_relative_to(fixture_root) for key in ['staging_app', 'staging_zip', 'destination_release', 'destination_zip', 'derived_data'])
        return base, dist, staging, name, env

    for mode, expected in [('missing', 4), ('sign-failure', 41), ('verify-failure', 42)]:
        base, dist, staging, name, env = seal_fixture(mode, mode, legacy=True)
        before = tree(dist)
        assert execute('seal-' + mode, ['zsh', '-f', '-c', 'set -euo pipefail\n' + seal], env) == expected
        assert tree(dist) == before
    for legacy, unit, label in [(True, False, 'legacy-conflict'), (False, True, 'sealed-conflict')]:
        base, dist, staging, name, env = seal_fixture(label, legacy=legacy, unit=unit)
        before = tree(dist)
        assert execute('seal-' + label, ['zsh', '-f', '-c', 'set -euo pipefail\n' + seal], env) == 4
        assert tree(dist) == before
    base, dist, staging, name, env = seal_fixture('success')
    assert execute('seal-success', ['zsh', '-f', '-c', 'set -euo pipefail\n' + seal], env) == 0
    unit = dist / name
    manifest = json.loads((unit / (name + '.manifest.json')).read_text())
    assert manifest['archive']['sha256'] == sha(unit / (name + '.zip'))
    assert manifest['archive']['length'] == (unit / (name + '.zip')).stat().st_size
    captured = json.loads(Path(env['source_identity_file']).read_text())
    assert manifest['sourceCommit'] == captured['commit'] and manifest['sourceDirty'] == captured['dirty']
    before = tree(dist)
    shutil.copytree(unit / 'QuotaView.app', staging / 'QuotaView.app')
    shutil.copy2(unit / (name + '.zip'), staging / (name + '.zip'))
    assert execute('seal-byte-identical-reuse', ['zsh', '-f', '-c', 'set -euo pipefail\n' + seal], env) == 0
    assert tree(dist) == before

    # Run the real source-identity verifier used by the seal block. Both clean
    # HEAD replacement and same-status dirty byte changes must be rejected.
    build_script = (ROOT / 'scripts/build-app.sh').read_text()
    capture_position = build_script.index('release-source-identity.py" capture')
    build_position = build_script.index('\nxcodebuild ')
    verify_positions = [index for index in range(len(build_script))
                        if build_script.startswith('release-source-identity.py" verify', index)]
    assert len(verify_positions) == 2 and capture_position < build_position < verify_positions[0] < verify_positions[1]
    for mutation in ['new-commit', 'dirty-change', 'dirty-then-clean', 'same-dirty-status']:
        base, dist, staging, name, env = seal_fixture('source-' + mutation)
        (dist / 'previous-release-sentinel').write_bytes(b'PRESERVE_PREVIOUS_RELEASE')
        before = tree(dist)
        project = Path(env['project_dir'])
        source = project / 'build-input.swift'
        original = source.read_text()
        if mutation in ['dirty-then-clean', 'same-dirty-status']:
            source.write_text('let capturedInput = 2\n')
            subprocess.run(['python3', str(ROOT / 'scripts/release-source-identity.py'), 'capture',
                            str(project), env['source_identity_file']], check=True, capture_output=True)
        source.write_text(original if mutation == 'dirty-then-clean' else 'let capturedInput = 3\n')
        if mutation == 'new-commit':
            subprocess.run(['git', '-C', str(project), 'add', 'build-input.swift'], check=True, capture_output=True)
            subprocess.run(['git', '-C', str(project), '-c', 'user.name=Synthetic Release Test',
                            '-c', 'user.email=audit@invalid.test', '-c', 'commit.gpgsign=false',
                            '-c', 'core.hooksPath=/dev/null', 'commit', '-q', '-m', 'Different clean input'],
                           check=True, capture_output=True)
        assert execute('seal-source-' + mutation, ['zsh', '-f', '-c', 'set -euo pipefail\n' + seal], env) == 4
        assert 'Release source changed' in (LOG / ('seal-source-' + mutation + '.log')).read_text()
        assert tree(dist) == before and not Path(env['destination_release']).exists()

    # Exercise the full appcast script using real ZIP/plist files, but every
    # signer, notarization command and public download is a synthetic mock.
    for mode in ['missing-manifest', 'public-mismatch', 'feed-verification-failure', 'enclosure-mismatch', 'success',
                 'history-success', 'missing-base', 'invalid-base-signature', 'explicit-initial-feed']:
        base = fixture_root / ('appcast-' + mode)
        project, archives, binaries = base / 'project', base / 'archives', base / 'bin'
        (project / 'scripts').mkdir(parents=True); (project / 'Support').mkdir()
        archives.mkdir(); binaries.mkdir()
        rg_path = shutil.which('rg')
        assert rg_path, 'The publishing script requires ripgrep'
        (binaries / 'rg').symlink_to(rg_path)
        shutil.copy2(ROOT / 'scripts/generate-appcast.sh', project / 'scripts/generate-appcast.sh')
        shutil.copy2(ROOT / 'Support/Info.plist', project / 'Support/Info.plist')
        app = base / 'payload/QuotaView.app'
        data = info(app); info(app / 'Contents/PlugIns/QuotaViewWidgetExtension.appex', True)
        version, display = data['CFBundleShortVersionString'], data['QuotaViewDisplayBuildNumber']
        release_name = f'QuotaView-v{version}-build.{display}'
        tag = f'v{version}-build.{display}'
        archive = archives / (release_name + '.zip')
        with zipfile.ZipFile(archive, 'w') as zipped:
            for file in app.rglob('*'):
                if file.is_file(): zipped.write(file, file.relative_to(app.parent).as_posix())
        sealed = {'format': 1, 'releaseName': release_name, 'sourceCommit': 'a' * 40,
                  'sourceDirty': False, 'signing': {'developerID': True, 'notarized': True},
                  'archive': {'name': archive.name, 'sha256': sha(archive), 'length': archive.stat().st_size, 'sparkleSignature': 'SYNTHETIC_SIGNATURE'}}
        manifest_path = archives / (release_name + '.manifest.json')
        if mode != 'missing-manifest': manifest_path.write_text(json.dumps(sealed))
        public = base / 'public.zip'
        public.write_bytes(b'PUBLIC_BYTES_DIFFER' if mode == 'public-mismatch' else archive.read_bytes())
        key_log = base / 'mock-key-access.txt'
        team = data['QuotaViewUpdateTeamIdentifier']
        tool(binaries / 'codesign', '#!/bin/zsh\nif [[ "$*" == *-dv* ]]; then\nprint "TeamIdentifier=' + team + '"\nprint "Authority=Developer ID Application: SYNTHETIC"\nfi\nexit 0\n')
        tool(binaries / 'xcrun', '#!/bin/zsh\nexit 0\n')
        tool(binaries / 'curl', '''#!/usr/bin/env python3
import os, shutil, sys
shutil.copyfile(os.environ['SYNTHETIC_PUBLIC_ZIP'], sys.argv[sys.argv.index('--output') + 1])
''')
        tool(binaries / 'sign_update', '''#!/usr/bin/env python3
import os, sys
from pathlib import Path
with open(os.environ['SYNTHETIC_KEY_LOG'], 'a') as log: log.write('MOCK ONLY\\n')
for argument in sys.argv[1:]:
    if argument.endswith('.xml') and Path(argument).is_file():
        generated = 'synthetic-generated' in Path(argument).read_text()
        if os.environ['SYNTHETIC_MODE'] == 'feed-verification-failure' and generated: sys.exit(42)
        if os.environ['SYNTHETIC_MODE'] == 'invalid-base-signature' and not generated: sys.exit(43)
''')
        url = f'https://github.com/Duoasa/QuotaView/releases/download/{tag}/{archive.name}'
        length = archive.stat().st_size + (1 if mode == 'enclosure-mismatch' else 0)
        xml = f'''<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>{data['CFBundleVersion']}</sparkle:version><sparkle:shortVersionString>{version}</sparkle:shortVersionString><sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion><enclosure url="{url}" length="{length}" sparkle:edSignature="SYNTHETIC_SIGNATURE"/></item></channel></rss>'''
        old_urls = [f'https://example.invalid/release-{number}/immutable.zip' for number in [1, 2]]
        old_xml = '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>'
        old_xml += ''.join(f'<item><sparkle:version>{number}</sparkle:version><enclosure url="{old_url}" length="7" sparkle:edSignature="OLD_SIGNATURE"/></item>'
                           for number, old_url in zip([1, 2], old_urls))
        old_xml += '</channel></rss><!-- sparkle-signatures: synthetic-old -->'
        generator = '''#!/usr/bin/env python3
import os, sys, xml.etree.ElementTree as ET
from pathlib import Path
ET.register_namespace('sparkle', 'http://www.andymatuschak.org/xml-namespaces/sparkle')
destination = Path(sys.argv[sys.argv.index('-o') + 1])
existing = ET.parse(destination).getroot() if destination.exists() else ET.fromstring('<rss><channel/></rss>')
if os.environ['SYNTHETIC_MODE'] == 'history-success':
    assert len(existing.findall('./channel/item')) == 2, 'The previous-version feed was not staged'
new = ET.fromstring(NEW_XML).find('./channel/item')
existing.find('channel').append(new)
destination.write_text(ET.tostring(existing, encoding='unicode') + '<!-- sparkle-signatures: synthetic-generated -->')
'''.replace('NEW_XML', repr(xml))
        tool(binaries / 'generate_appcast', generator)
        feed = archives / 'appcast.xml'
        prior_feed = base / 'previous-version/appcast.xml'
        prior_feed.parent.mkdir()
        prior_feed.write_text(old_xml)
        prior_sha = sha(prior_feed)
        if mode not in ['history-success', 'missing-base', 'invalid-base-signature', 'explicit-initial-feed']:
            feed.write_text(old_xml)
        before = tree(archives)
        env = {'PATH': str(binaries) + ':/usr/bin:/bin:/usr/sbin:/sbin',
               'SPARKLE_KEY_ACCOUNT': 'SYNTHETIC_NO_KEYCHAIN',
               'SPARKLE_SIGN_UPDATE': str(binaries / 'sign_update'),
               'SPARKLE_GENERATE_APPCAST': str(binaries / 'generate_appcast'),
               'SYNTHETIC_PUBLIC_ZIP': str(public), 'SYNTHETIC_KEY_LOG': str(key_log), 'SYNTHETIC_MODE': mode}
        if mode in ['history-success', 'invalid-base-signature']:
            env['SPARKLE_APPCAST_BASE_FEED'] = str(prior_feed)
        if mode == 'explicit-initial-feed':
            env['SPARKLE_APPCAST_INITIAL_FEED'] = 'YES'
        code = execute('appcast-' + mode, ['zsh', '-f', str(project / 'scripts/generate-appcast.sh'), str(archives), tag], env)
        if mode in ['success', 'history-success', 'explicit-initial-feed']:
            assert code == 0
            result = ET.parse(feed).getroot()
            items = result.findall('./channel/item')
            expected_count = 1 if mode == 'explicit-initial-feed' else 3
            assert len(items) == expected_count
            if mode != 'explicit-initial-feed':
                assert [item.find('enclosure').get('url') for item in items[:2]] == old_urls
            current = items[-1]
            namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
            assert current.findtext(namespace + 'version') == data['CFBundleVersion']
            assert current.find('enclosure').get('url') == url
            assert current.find('enclosure').get('length') == str(archive.stat().st_size)
            assert current.find('enclosure').get(namespace + 'edSignature') == sealed['archive']['sparkleSignature']
            assert sha(archive) == before[archive.name]
            assert sha(manifest_path) == before[manifest_path.name]
        else:
            assert code != 0 and tree(archives) == before
        assert sha(prior_feed) == prior_sha
        if mode in ['missing-manifest', 'public-mismatch', 'missing-base']:
            assert not key_log.exists()
        if mode == 'missing-base':
            assert 'Missing previous verified appcast' in (LOG / 'appcast-missing-base.log').read_text()

(LOG / 'release-smoke-results.json').write_text(json.dumps(RESULTS, indent=2) + '\n')
print('Synthetic release atomicity and appcast binding fixtures passed; no real keys/signing/downloads.')
