#!/usr/bin/env python3
"""Capture and verify release build inputs without exposing their contents."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys


def source_identity(root):
    environment = dict(os.environ, GIT_OPTIONAL_LOCKS='0')

    def git(*arguments):
        return subprocess.check_output(['git', '-C', str(root), *arguments], env=environment)

    commit = git('rev-parse', 'HEAD').decode().strip()
    status = git('status', '--porcelain=v1', '-z', '--untracked-files=all').decode('utf-8', 'surrogateescape')
    paths = sorted(set(git('ls-files', '-z', '--cached', '--others', '--exclude-standard').split(b'\0')) - {b''})
    entries = []
    for encoded in paths:
        name = os.fsdecode(encoded)
        path = root / name
        if path.is_symlink():
            entry = [name, 'symlink', os.readlink(path)]
        elif path.is_file():
            digest = hashlib.sha256()
            with path.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
            entry = [name, 'file', path.stat().st_mode & 0o777, digest.hexdigest()]
        elif path.is_dir():
            raise ValueError('Release source contains a directory Git entry; unsupported submodule: ' + name)
        else:
            entry = [name, 'missing']
        entries.append(entry)
    fingerprint = hashlib.sha256(json.dumps(entries, ensure_ascii=True, separators=(',', ':')).encode()).hexdigest()
    return {'format': 1, 'commit': commit, 'status': status, 'dirty': bool(status), 'sha256': fingerprint}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['capture', 'verify'])
    parser.add_argument('source_root', type=Path)
    parser.add_argument('snapshot', type=Path)
    args = parser.parse_args()
    current = source_identity(args.source_root.resolve())
    if args.action == 'capture':
        args.snapshot.write_text(json.dumps(current, indent=2) + '\n')
    elif current != json.loads(args.snapshot.read_text()):
        raise ValueError('Release source changed after build inputs were captured; refusing to seal')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print('Cannot verify release source identity: ' + str(error), file=sys.stderr)
        sys.exit(4)
