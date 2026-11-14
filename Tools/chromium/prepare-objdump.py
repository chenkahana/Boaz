#!/opt/homebrew/bin/python3.12
"""Install the pinned LLVM inspection supplement without replacing clang."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
LOCK = HERE / 'toolchains.objdump.json'
spec = importlib.util.spec_from_file_location('toolchains', HERE / 'prepare-toolchains.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)


def install(pin):
    root = Path(pin['root'])
    if Path.cwd() != root.parent or os.environ.get('TMPDIR') != str(root.parent / 'tmp'):
        raise ValueError('Run installation through the volume guard')
    with (root.parent / '.build.lock').open() as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise ValueError('Volume guard lock not held')
    source = root / 'chromium/src'
    state = root / 'toolchains'
    destination = source / pin['destination']
    archive = root / 'downloads' / Path(pin['object']).name
    stage = state / 'llvmobjdump.stage'
    receipt = state / 'llvmobjdump.installed.json'
    for path in (root, source, state, destination, archive.parent):
        if path.resolve() != path or not path.is_dir():
            raise ValueError(f'Missing or redirected directory: {path}')
    if (source / 'chrome/VERSION').read_text().splitlines() != [
            'MAJOR=157', 'MINOR=0', 'BUILD=8103', 'PATCH=51']:
        raise ValueError('Unexpected Chromium revision')
    clang = json.loads((state / 'clang.installed.json').read_text())
    if clang['recipe_sha256'] != common.sha(HERE / 'toolchains.lock.json'):
        raise ValueError('Installed clang belongs to another recipe')
    common.download(pin, archive)
    expected = {'lock_sha256': common.sha(LOCK), 'tree': pin['tree']}
    if receipt.is_symlink() or (receipt.exists() and json.loads(receipt.read_text()) != expected):
        raise ValueError('Supplement receipt differs from pin')
    if not stage.exists():
        common.extract(archive, stage)
    if stage.is_symlink() or common.tree(stage) != pin['tree']:
        raise ValueError('Preserved supplement stage differs from pin')
    # Inspect every collision before writing any destination file.
    for rel, wanted in pin['tree'].items():
        path = destination / rel
        if path.parent.resolve() != path.parent:
            raise ValueError(f'Redirected destination parent: {path}')
        if rel in clang['tree'] and clang['tree'][rel] != wanted:
            raise ValueError(f'Supplement conflicts with base clang: {rel}')
        if os.path.lexists(path):
            actual = (['link', os.readlink(path)] if path.is_symlink() else
                      ['file', common.sha(path), bool(path.stat().st_mode & 0o111)])
            if actual != wanted:
                raise ValueError(f'Destination collision: {path}')
    for rel, wanted in pin['tree'].items():
        path = destination / rel
        if os.path.lexists(path):
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        if wanted[0] == 'link':
            path.symlink_to(wanted[1])
        else:
            # Hard-link a verified staging inode; exclusive destination creation.
            os.link(stage / rel, path)
    for rel, wanted in pin['tree'].items():
        path = destination / rel
        actual = (['link', os.readlink(path)] if path.is_symlink() else
                  ['file', common.sha(path), bool(path.stat().st_mode & 0o111)])
        if actual != wanted:
            raise ValueError(f'Installed supplement mismatch: {path}')
    if not receipt.exists():
        common.write_new(receipt, expected)
    print(json.dumps({'status': 'verified', 'package': pin['package_version'],
                      'tools': sorted(pin['tree']), 'receipt': str(receipt)}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--prepare', action='store_true')
    mode.add_argument('--dry-run', action='store_true')
    mode.add_argument('--guarded', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    pin = json.loads(LOCK.read_text())
    command = ['/opt/homebrew/bin/python3.12', str(HERE.parent / 'cef/run-build.py'), '--',
               '/opt/homebrew/bin/python3.12', str(Path(__file__).resolve()), '--guarded']
    if args.guarded:
        install(pin)
    elif args.prepare:
        subprocess.run(command, check=True)
    else:
        print(json.dumps({'command': command, 'package': pin}, indent=2))

if __name__ == '__main__':
    main()
