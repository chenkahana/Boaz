#!/opt/homebrew/bin/python3.12
"""Development-sign an assembled app with Chromium's pinned official signer."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path('/Volumes/BoazBuild/cef/direct')
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--guarded', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not args.guarded:
        return subprocess.call(['/opt/homebrew/bin/python3.12', str(HERE.parent / 'cef/run-build.py'), '--',
            '/opt/homebrew/bin/python3.12', str(Path(__file__).resolve()), *sys.argv[1:], '--guarded'])
    if Path.cwd() != ROOT.parent or os.environ.get('TMPDIR') != str(ROOT.parent / 'tmp'):
        raise RuntimeError('Signing requires the verified SSD guard')
    source, output = Path(args.input), Path(args.output)
    for path in (source, output):
        if not path.is_absolute() or path.resolve() != path or not path.is_relative_to(ROOT / 'artifacts'):
            raise RuntimeError('Signing paths must be canonical unpublished artifacts')
    if output.exists() or output.is_symlink():
        raise RuntimeError('Refusing to overwrite signed output')
    app = source / 'Chromium.app'
    assembly = source / 'Chromium.assembly.json'
    if not assembly.is_file() or not app.is_dir():
        raise RuntimeError('Input must be a completed application assembly')
    output.mkdir()
    packaging = source / 'Chromium Packaging'
    if packaging.exists():
        raise RuntimeError('Preserve this prior signing input; use a new assembly')
    shutil.copytree(ROOT / 'chromium/src/out/BoazDevelopment/Chromium Packaging', packaging)
    framework = app / 'Contents/Frameworks/Sparkle.framework'
    targets = []
    for path in framework.rglob('*'):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open('rb') as stream:
            magic = stream.read(4)
        if magic in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'):
            targets.append(path)
    targets += sorted((p for p in framework.rglob('*') if p.suffix in ('.app', '.xpc') and not p.is_symlink()),
                      key=lambda p: len(p.parts), reverse=True)
    targets += [framework, app / 'Contents/Frameworks/libBoazApplicationUI.dylib']
    with (output / 'sign.log').open('x') as log:
        for target in targets:
            subprocess.run(['/usr/bin/codesign', '--force', '--sign', args.identity, '--timestamp',
                            '--options', 'runtime', '--preserve-metadata=identifier,entitlements', str(target)],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run(['/opt/homebrew/bin/python3.12', str(packaging / 'sign_chrome.py'),
                        '--identity', args.identity, '--development', '--input', str(source),
                        '--output', str(output), '--disable-packaging', '--notarize', 'none',
                        '--no-embed-development-provisioning-profile'],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    with (output / 'development-signing.json').open('x') as stream:
        json.dump({'assembly': str(assembly), 'identity': args.identity,
                   'application': str(output / 'stable/Chromium.app'),
                   'development_only': True, 'notarized': False, 'published': False}, stream, indent=2)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
