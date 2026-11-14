#!/opt/homebrew/bin/python3.12
"""Prepare and verify three local Sparkle delta candidates; never publish."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = Path('/Volumes/BoazBuild/cef/direct')
spec = importlib.util.spec_from_file_location('candidate_packager', HERE / 'package-candidate.py')
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', value):
        raise RuntimeError('Expected numeric version with up to three components')
    parts = tuple(map(int, value.split('.')))
    return parts + (0,) * (3 - len(parts))


def canonical(value):
    path = Path(value)
    if not path.is_absolute() or path.resolve() != path:
        raise RuntimeError('Paths must be absolute and canonical')
    return path


def inspect(app):
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if info.get('CFBundleIdentifier') != 'com.chenkahana.boaz':
        raise RuntimeError('Only production Boaz application identities are accepted')
    version(info.get('CFBundleVersion'))
    packager.run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
    return info


def prepare(args):
    candidate = canonical(args.candidate)
    previous = [canonical(value) for value in args.previous]
    output, tools = canonical(args.output), canonical(args.sparkle_bin)
    if len(set(previous + [candidate])) != 4:
        raise RuntimeError('Candidate and three previous apps must be distinct')
    if (not output.is_relative_to(ROOT / 'artifacts') or output == ROOT / 'artifacts'
            or output.exists() or output.is_symlink()
            or any(output.is_relative_to(app) for app in previous + [candidate])):
        raise RuntimeError('Output must be a new independent artifact directory')
    for name in ('BinaryDelta', 'sign_update', 'generate_keys'):
        if not (tools / name).is_file() or not os.access(tools / name, os.X_OK):
            raise RuntimeError('Required Sparkle executable unavailable')
    info = inspect(candidate)
    old_infos = [inspect(app) for app in previous]
    builds = [version(item['CFBundleVersion']) for item in old_infos]
    if len(set(builds)) != 3 or any(build >= version(info['CFBundleVersion']) for build in builds):
        raise RuntimeError('Previous builds must be distinct and older than candidate')
    key = info.get('SUPublicEDKey')
    public, _ = packager.run(str(tools / 'generate_keys'), '-p')
    if not key or public.decode().strip() != key or any(item.get('SUPublicEDKey') != key for item in old_infos):
        raise RuntimeError('All apps and the signing key must share a Sparkle public key')
    for app in previous:
        with (app / 'Contents/Frameworks/Sparkle.framework/Resources/Info.plist').open('rb') as stream:
            sdk = plistlib.load(stream)
        if version(sdk.get('CFBundleShortVersionString')) < (2, 10, 1):
            raise RuntimeError('Format 4 requires approved previous Sparkle SDK at least 2.10.1')
    inputs = {str(app): packager.inventory(app) for app in [candidate, *previous]}
    output.mkdir(parents=True)
    receipt = {'candidate': str(candidate), 'candidate_build': info['CFBundleVersion'],
               'published': False, 'delta_preparation_complete': False,
               'runtime_installation_verified': False, 'input_inventories': inputs,
               'tools': {name: {'path': str(tools / name), 'sha256': packager.digest(tools / name)}
                         for name in ('BinaryDelta', 'sign_update', 'generate_keys')}, 'deltas': []}
    receipt_path = output / 'delta-candidates.json'
    def save():
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    save()
    for index, (old, old_info) in enumerate(zip(previous, old_infos)):
        delta = output / f'from-{old_info["CFBundleVersion"]}.delta'
        reconstructed = output / f'reconstructed-{index}.app'
        packager.run(str(tools / 'BinaryDelta'), 'create', '--version', '4', '--compression', 'lzma',
                     str(old), str(candidate), str(delta))
        entry = {'source': str(old), 'source_build': old_info['CFBundleVersion'],
                 'candidate_build': info['CFBundleVersion'], 'format': 4, 'compression': 'lzma',
                 'file_url': delta.as_uri(), 'bytes': delta.stat().st_size,
                 'sha256': packager.digest(delta), 'verified': False}
        receipt['deltas'].append(entry)
        save()
        if entry['bytes'] > 40_000_000:
            raise RuntimeError('Delta exceeds 40000000 bytes; artifacts preserved')
        packager.run(str(tools / 'BinaryDelta'), 'apply', str(old), str(reconstructed), str(delta))
        if packager.inventory(reconstructed) != inputs[str(candidate)]:
            raise RuntimeError('Reconstructed application differs from candidate')
        rebuilt = inspect(reconstructed)
        if rebuilt['CFBundleVersion'] != info['CFBundleVersion']:
            raise RuntimeError('Reconstructed build differs from candidate')
        signature, _ = packager.run(str(tools / 'sign_update'), '-p', str(delta))
        signature = signature.decode().strip()
        if not signature:
            raise RuntimeError('Sparkle returned no signature')
        packager.run(str(tools / 'sign_update'), '--verify', str(delta), signature)
        entry.update({'signature': signature, 'verified': True, 'reconstructed': str(reconstructed)})
        save()
    for app in [candidate, *previous]:
        if packager.inventory(app) != inputs[str(app)]:
            raise RuntimeError('An input application changed during preparation')
    receipt['delta_preparation_complete'] = True
    save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--previous', action='append', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--sparkle-bin', required=True)
    parser.add_argument('--no-publish', required=True, action='store_true')
    parser.add_argument('--guarded', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if len(args.previous) != 3:
        parser.error('Exactly three --previous applications are required')
    if not args.guarded:
        return subprocess.call(['/opt/homebrew/bin/python3.12', str(HERE.parent / 'cef/run-build.py'), '--',
            '/opt/homebrew/bin/python3.12', str(Path(__file__).resolve()), *sys.argv[1:], '--guarded'])
    if Path.cwd() != ROOT.parent or os.environ.get('TMPDIR') != str(ROOT.parent / 'tmp'):
        raise RuntimeError('Delta preparation requires verified SSD guard')
    with (ROOT.parent / '.build.lock').open('r') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise RuntimeError('Build guard is not holding its lock')
    prepare(args)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print(f'Delta preparation failed: {error}', file=sys.stderr)
        sys.exit(1)
