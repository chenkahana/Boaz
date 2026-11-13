#!/opt/homebrew/bin/python3.12
"""Assemble an unpublished development app from completed Chromium and UI builds."""
import argparse
import hashlib
import json
import os
import plistlib
from pathlib import Path
import shutil
import subprocess

ROOT = Path('/Volumes/BoazBuild/cef/direct')
HERE = Path(__file__).resolve().parent


def checked(path):
    path = Path(path)
    if not path.is_absolute() or path.resolve() != path or not path.is_relative_to(ROOT):
        raise RuntimeError(f'Artifact must be a canonical path under {ROOT}: {path}')
    return path


def assemble(base, receipt, output, native_launch=False):
    base, receipt, output = map(checked, (base, receipt, output))
    if output.exists() or output.is_symlink():
        raise RuntimeError('Refusing to overwrite an existing application artifact')
    record = json.loads(receipt.read_text())
    library = checked(record['immutable_copy'])
    resources = [checked(item['staged']) for item in record['resources_and_frameworks']]
    bundle = next((p for p in resources if p.name == 'BoazResources.bundle'), None)
    sparkle = next((p for p in resources if p.name == 'Sparkle.framework'), None)
    if bundle is None or sparkle is None or not library.is_file():
        raise RuntimeError('Completed UI build must include its library, resources, and Sparkle')
    for name in ('Assets.car', 'easylist_min_content_blocker.json'):
        if not (bundle / 'Contents/Resources' / name).is_file():
            raise RuntimeError(f'Missing Boaz resource: {name}')
    if not (base / 'Contents/MacOS/Chromium').is_file():
        raise RuntimeError('Expected the pinned Chromium development app')
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['/usr/bin/ditto', '--clone', str(base), str(output)], check=True)
    if native_launch:
        info = output / 'Contents/Info.plist'
        with info.open('rb') as stream:
            metadata = plistlib.load(stream)
        metadata.update({'CFBundleIdentifier': 'com.chenkahana.boaz.chromium.dev',
                         'CFBundleName': 'Boaz Development', 'CFBundleDisplayName': 'Boaz Development',
                         'BoazNativeApplication': True, 'BoazDistributionChannel': 'development',
                         'CrProductDirName': 'Boaz Chromium Development'})
        with info.open('wb') as stream:
            plistlib.dump(metadata, stream)
    frameworks, destination = output / 'Contents/Frameworks', output / 'Contents/Resources'
    for item in [library, *resources]:
        if item.name == 'Assets.car':
            continue  # The catalog belongs to BoazResources.bundle.
        parent = frameworks if item.suffix in ('.dylib', '.framework') else destination
        target = parent / item.name
        if target.exists() or target.is_symlink():
            raise RuntimeError(f'Artifact conflicts with Chromium resource: {target}')
        if item.is_dir():
            shutil.copytree(item, target, symlinks=True)
        else:
            shutil.copy2(item, target)
    manifest = {'application': str(output), 'base': str(base), 'ui_receipt': str(receipt),
                'ui_sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
                'signed': False, 'published': False,
                'remaining': 'Development signing, launch acceptance, Boaz distribution branding and release gates.'}
    with output.with_suffix('.assembly.json').open('x') as stream:
        json.dump(manifest, stream, indent=2)
    print(json.dumps(manifest, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-app', required=True)
    parser.add_argument('--ui-receipt', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--native-launch', action='store_true', help='Requires packaged-launch-capable host; uses isolated development identity')
    parser.add_argument('--guarded', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not args.guarded:
        command = ['/opt/homebrew/bin/python3.12', str(HERE.parent / 'cef/run-build.py'), '--',
                   '/opt/homebrew/bin/python3.12', str(Path(__file__).resolve()), '--guarded',
                   '--base-app', args.base_app, '--ui-receipt', args.ui_receipt, '--output', args.output] + (['--native-launch'] if args.native_launch else [])
        return subprocess.call(command)
    if Path.cwd() != ROOT.parent or os.environ.get('TMPDIR') != str(ROOT.parent / 'tmp'):
        raise RuntimeError('Assembly requires the verified SSD guard')
    assemble(args.base_app, args.ui_receipt, args.output, args.native_launch)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
