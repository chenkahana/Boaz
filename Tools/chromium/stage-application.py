#!/opt/homebrew/bin/python3.12
"""Assemble an unpublished development app from completed Chromium and UI builds."""
import argparse
import hashlib
import json
import os
import plistlib
import re
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


def blocking_assets(blocker_receipt):
    lock = json.loads((HERE / 'adblock/assets.lock.json').read_text())
    if (lock.get('schema_version') != 1 or
            lock.get('native_library_sha256') != blocker_receipt['library_sha256']):
        raise RuntimeError('Blocking assets require their validated native library')
    directory = checked(lock['artifact_directory'])
    files = lock.get('files', {})
    if not {'rules.txt', 'resources.json', 'assets.json', 'NOTICE'}.issubset(files):
        raise RuntimeError('Blocking asset inventory is incomplete')
    result = {}
    total = 0
    for name, expected in files.items():
        if not re.fullmatch(r'[A-Za-z0-9_.-]+', name) or name in ('.', '..'):
            raise RuntimeError('Invalid blocking asset filename')
        size = expected['size_bytes']
        if type(size) is not int or size < 0 or size > 16 * 1024 * 1024:
            raise RuntimeError('Blocking asset size exceeds bounds')
        total += size
        if total > 32 * 1024 * 1024:
            raise RuntimeError('Blocking asset inventory exceeds bounds')
        path = checked(directory / name)
        if not path.is_file() or path.stat().st_size != size:
            raise RuntimeError('Blocking asset type or size changed')
        with path.open('rb') as stream:
            data = stream.read(size + 1)
        if len(data) != size or hashlib.sha256(data).hexdigest() != expected['sha256']:
            raise RuntimeError('Blocking asset checksum changed')
        result[name] = data
    return result


def assemble(base, receipt, output, native_launch=False, production_version=None, production_build=None):
    base, receipt, output = map(checked, (base, receipt, output))
    expected_name = 'Boaz.app' if production_version else 'Chromium.app'
    if output.name != expected_name:
        raise RuntimeError(f'Output must name the application bundle {expected_name}, not its parent directory')
    if output.exists() or output.is_symlink():
        raise RuntimeError('Refusing to overwrite an existing application artifact')
    record = json.loads(receipt.read_text())
    library = checked(record['immutable_copy'])
    native_receipt = json.loads((ROOT / 'native-built.json').read_text())
    source_lock = json.loads((HERE / 'source.lock.json').read_text())
    framework = base / 'Contents/Frameworks/Chromium Framework.framework/Versions' / source_lock['chromium_version'] / 'Chromium Framework'
    with framework.open('rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != native_receipt['framework_sha256']:
            raise RuntimeError('Base application differs from the completed native build receipt')
    blocker_receipt = native_receipt['blocking']
    blocker = checked(blocker_receipt['library'])
    if (blocker.name != 'libboaz_adblock.dylib' or
            hashlib.sha256(blocker.read_bytes()).hexdigest() != blocker_receipt['library_sha256']):
        raise RuntimeError('Completed content-blocking library checksum differs')
    verified_assets = blocking_assets(blocker_receipt)
    cli = checked(record['cli'])
    if not cli.is_file() or not os.access(cli, os.X_OK):
        raise RuntimeError('Completed UI build must include the executable CLI')
    resources = [checked(item['staged']) for item in record['resources_and_frameworks']]
    distribution = record.get('distribution_info')
    if not isinstance(distribution, dict) or not distribution.get('SUPublicEDKey'):
        raise RuntimeError('Build receipt requires resolved Boaz distribution metadata')
    if not any(item.name == 'Boaz.icns' and item.is_file() for item in resources):
        raise RuntimeError('Build receipt requires the Boaz application icon')
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
        metadata['CFBundleIconFile'] = 'Boaz.icns'
        metadata.pop('CFBundleIconName', None)
        if production_version:
            metadata.update({key: value for key, value in distribution.items() if key.startswith('SU')})
            metadata.update({'CFBundleIdentifier': 'com.chenkahana.boaz', 'CFBundleName': 'Boaz',
                             'CFBundleDisplayName': 'Boaz', 'BoazDistributionChannel': 'production',
                             'CrProductDirName': 'Boaz/Chromium',
                             'CFBundleShortVersionString': production_version, 'CFBundleVersion': production_build})
        else:
            metadata['SUEnableAutomaticChecks'] = False
            metadata.pop('SUFeedURL', None)
        metadata['CFBundleURLTypes'] = distribution.get('CFBundleURLTypes', [])
        schemes = {scheme for entry in metadata['CFBundleURLTypes']
                   for scheme in entry.get('CFBundleURLSchemes', [])}
        if not {'http', 'https'}.issubset(schemes):
            raise RuntimeError('Boaz distribution must register both HTTP and HTTPS')
        for key, value in list(metadata.items()):
            if key.startswith('NS') and key.endswith('UsageDescription') and isinstance(value, str):
                metadata[key] = value.replace('Chromium', 'Boaz')
        for key, value in distribution.items():
            if key.startswith('NS') and key.endswith('UsageDescription'):
                metadata[key] = value
        metadata['LSApplicationCategoryType'] = 'public.app-category.productivity'
        url_types = metadata['CFBundleURLTypes']
        url_types.append({'CFBundleURLName': 'Boaz commands', 'CFBundleTypeRole': 'Viewer',
                          'CFBundleURLSchemes': ['boaz']})
        with info.open('wb') as stream:
            plistlib.dump(metadata, stream)
    cli_target = output / 'Contents/MacOS/boaz'
    if cli_target.exists() or cli_target.is_symlink():
        raise RuntimeError('CLI conflicts with base application')
    shutil.copy2(cli, cli_target)
    frameworks, destination = output / 'Contents/Frameworks', output / 'Contents/Resources'
    for item in [library, blocker, *resources]:
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
    blocking_destination = destination / 'BoazBlocking'
    blocking_destination.mkdir()
    for name, data in verified_assets.items():
        with (blocking_destination / name).open('xb') as stream:
            stream.write(data)
    manifest = {'application': str(output), 'base': str(base), 'ui_receipt': str(receipt),
                'ui_sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
                'blocking_sha256': blocker_receipt['library_sha256'],
                'blocking_assets': {name: hashlib.sha256(data).hexdigest() for name, data in verified_assets.items()},
                'signed': False, 'published': False, 'production_metadata': bool(production_version),
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
    parser.add_argument('--production-version')
    parser.add_argument('--production-build')
    parser.add_argument('--guarded', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if bool(args.production_version) != bool(args.production_build):
        parser.error('Production version and build must be supplied together')
    if args.production_version and (not args.native_launch or
            not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,3}', args.production_version) or
            not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,3}', args.production_build)):
        parser.error('Production metadata requires native launch and numeric version/build values')
    if not args.guarded:
        command = ['/opt/homebrew/bin/python3.12', str(HERE.parent / 'cef/run-build.py'), '--',
                   '/opt/homebrew/bin/python3.12', str(Path(__file__).resolve()), '--guarded',
                   '--base-app', args.base_app, '--ui-receipt', args.ui_receipt, '--output', args.output] + (['--native-launch'] if args.native_launch else [])
        if args.production_version:
            command += ['--production-version', args.production_version, '--production-build', args.production_build]
        return subprocess.call(command)
    if Path.cwd() != ROOT.parent or os.environ.get('TMPDIR') != str(ROOT.parent / 'tmp'):
        raise RuntimeError('Assembly requires the verified SSD guard')
    assemble(args.base_app, args.ui_receipt, args.output, args.native_launch, args.production_version, args.production_build)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
