#!/opt/homebrew/bin/python3.12
"""Generate or explicitly build the native Boaz UI library without publishing."""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
import plistlib
from pathlib import Path
import shutil
import subprocess
import uuid

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
PROJECT = REPO / 'build/chromium-app'
ROOT = Path('/Volumes/BoazBuild/cef/direct')
APP = ROOT / 'app'
PYTHON = '/opt/homebrew/bin/python3.12'


def generate():
    if PROJECT.resolve() != PROJECT:
        raise RuntimeError('Generated project directory is redirected')
    PROJECT.mkdir(parents=True, exist_ok=True)
    subprocess.run(['/opt/homebrew/bin/xcodegen', 'generate', '--spec',
                    str(REPO / 'project-chromium.yml'), '--project', str(PROJECT)],
                   cwd=REPO, env=dict(os.environ, BOAZ_CHROMIUM_REPO_ROOT=str(REPO)), check=True)


def available(path):
    if path.exists():
        result = subprocess.run(['/usr/sbin/lsof', '-t', '--', str(path)],
                                text=True, capture_output=True)
        if result.returncode not in (0, 1) or result.stdout.strip():
            raise RuntimeError(f'Library is in use or could not be checked: {path}')


def clone_cache(runs, source_name, destination):
    source = runs / source_name
    receipt = source / 'artifacts/build.json'
    if source.resolve() != source or not source.is_dir():
        raise RuntimeError('Cache source run is missing or redirected')
    if receipt.resolve() != receipt or not receipt.is_file():
        raise RuntimeError('Cache source requires a completed, unredirected build receipt')
    metadata = json.loads(receipt.read_text())
    command = metadata.get('command', [])
    project = str(PROJECT / 'BoazChromiumUI.xcodeproj')
    if not isinstance(command, list) or '-project' not in command:
        raise RuntimeError('Cache source receipt has no project command')
    index = command.index('-project') + 1
    if index >= len(command) or command[index] != project:
        raise RuntimeError('Cache source was built from another generated project')
    for name in ('DerivedData', 'SourcePackages'):
        directory = source / name
        if directory.resolve() != directory or not directory.is_dir():
            raise RuntimeError(f'Cache directory is missing or redirected: {directory}')
        # Relative, contained framework links survive relocation. Absolute links
        # could send incremental writes back into an immutable previous run.
        for parent, directories, files in os.walk(directory, followlinks=False):
            for child in directories + files:
                path = Path(parent) / child
                if path.is_symlink():
                    target = Path(os.readlink(path))
                    if target.is_absolute() or not path.resolve().is_relative_to(directory):
                        raise RuntimeError(f'Cache link cannot be safely relocated: {path}')
        target = destination / name
        if target.exists() or target.is_symlink():
            raise RuntimeError(f'Cache destination already exists: {target}')
        subprocess.run(['/usr/bin/ditto', '--clone', str(directory), str(target)], check=True)


def build(jobs, resume_run=None, cache_from=None):
    abi_header = HERE / "host/boaz_host.h"
    abi_header_sha256 = hashlib.sha256(abi_header.read_bytes()).hexdigest()
    if Path.cwd() != ROOT.parent or os.environ.get('TMPDIR') != str(ROOT.parent / 'tmp'):
        raise RuntimeError('Build requires the verified volume guard')
    with (ROOT.parent / '.build.lock').open() as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise RuntimeError('Volume guard lock is not held')
    for path in (ROOT, APP):
        if path.resolve() != path:
            raise RuntimeError(f'Redirected application build path: {path}')
    APP.mkdir(exist_ok=True)
    final = APP / 'libBoazApplicationUI.dylib'
    if final.is_symlink():
        raise RuntimeError('Library destination is a symlink')
    available(final)
    generate()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex
    runs = APP / 'runs'
    run = runs / (resume_run or stamp)
    if runs.resolve() != runs or run.resolve() != run:
        raise RuntimeError('Application run directory is redirected')
    if resume_run:
        if not run.is_dir():
            raise RuntimeError('Resume run does not exist or is not a directory')
        receipt = run / 'artifacts/build.json'
        if receipt.exists() or receipt.is_symlink():
            raise RuntimeError('Resume run already has a completed build receipt')
    else:
        run.mkdir(parents=True)
    if cache_from:
        if resume_run:
            raise RuntimeError('Cannot combine resume and completed-run cache')
        clone_cache(runs, cache_from, run)
    for name in ('tmp', 'cache', 'artifacts', 'DerivedData', 'SourcePackages'):
        directory = run / name
        if directory.resolve() != directory:
            raise RuntimeError(f'Redirected run directory: {directory}')
        directory.mkdir(exist_ok=True)
    artifacts = run / 'artifacts'
    if resume_run:
        artifacts = artifacts / ('resume-' + stamp)
        artifacts.mkdir()
    log_path = run / (f'xcodebuild-{stamp}.log' if resume_run else 'xcodebuild.log')
    result_path = run / (f'Build-{stamp}.xcresult' if resume_run else 'Build.xcresult')
    env = dict(os.environ, TMPDIR=str(run / 'tmp'), XDG_CACHE_HOME=str(run / 'cache'),
               CLANG_MODULE_CACHE_PATH=str(run / 'cache/clang'),
               SWIFT_MODULE_CACHE_PATH=str(run / 'cache/swift'))
    command = ['xcrun', 'xcodebuild', '-project', str(PROJECT / 'BoazChromiumUI.xcodeproj'),
               '-scheme', 'Boaz-ChromiumUI', '-configuration', 'Release',
               '-destination', 'generic/platform=macOS', '-jobs', str(jobs),
               '-derivedDataPath', str(run / 'DerivedData'),
               '-clonedSourcePackagesDirPath', str(run / 'SourcePackages'),
               '-resultBundlePath', str(result_path),
               'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'build']
    print(f'Application build log: {log_path}', flush=True)
    with log_path.open('x') as log:
        subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    if hashlib.sha256(abi_header.read_bytes()).hexdigest() != abi_header_sha256:
        raise RuntimeError('Bridge header changed during the UI build; no completed receipt was written')
    products = run / 'DerivedData/Build/Products/Release'
    library = products / 'libBoazApplicationUI.dylib'
    if not library.is_file() or library.is_symlink():
        raise RuntimeError('Expected dynamic library was not produced')
    staged = artifacts / 'libBoazApplicationUI.dylib'
    shutil.copy2(library, staged)
    cli = products / 'boaz'
    if not cli.is_file() or cli.is_symlink() or not os.access(cli, os.X_OK):
        raise RuntimeError('Expected bundled CLI was not produced')
    staged_cli = artifacts / 'boaz'
    shutil.copy2(cli, staged_cli)
    resources = []
    for item in sorted(products.iterdir()):
        if item.suffix not in ('.bundle', '.car', '.metallib', '.framework'):
            continue
        copied = artifacts / item.name
        if item.is_symlink():
            raise RuntimeError(f'Unexpected top-level resource symlink: {item}')
        if item.is_dir():
            shutil.copytree(item, copied, symlinks=True)
        else:
            shutil.copy2(item, copied)
        resources.append({'source': str(item), 'staged': str(copied)})
    resource_bundle = artifacts / 'BoazResources.bundle'
    bundle_contents = resource_bundle / 'Contents'
    bundle_resources = bundle_contents / 'Resources'
    bundle_resources.mkdir(parents=True)
    asset_catalog = products / 'Assets.car'
    if not asset_catalog.is_file():
        raise RuntimeError('Boaz asset catalog was not produced')
    shutil.copy2(asset_catalog, bundle_resources / 'Assets.car')
    shutil.copy2(REPO / 'Apps/Browser/easylist_min_content_blocker.json', bundle_resources)
    with (bundle_contents / 'Info.plist').open('xb') as stream:
        plistlib.dump({'CFBundleIdentifier': 'com.chenkahana.boaz.resources',
                      'CFBundleName': 'BoazResources', 'CFBundlePackageType': 'BNDL',
                      'CFBundleVersion': '1'}, stream)
    resources.append({'source': str(REPO), 'staged': str(resource_bundle)})
    available(final)
    previous = None
    if final.exists():
        previous = APP / f'libBoazApplicationUI.previous-{stamp}.dylib'
        final.rename(previous)
    os.link(staged, final)
    distribution = json.loads(subprocess.check_output(
        ['xcodegen', 'dump', '--spec', str(REPO / 'project-dmg.yml'), '--type', 'json'], cwd=REPO))
    distribution_info = distribution['targets']['Boaz-macOS']['info']['properties']
    iconset = artifacts / 'Boaz.iconset'
    iconset.mkdir()
    icon_source = REPO / 'Apps/Shared/Resources/Assets.xcassets/AppIcon.appiconset'
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            filename = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
            shutil.copy2(icon_source / f'mac-{size * scale}.png', iconset / filename)
    icon = artifacts / 'Boaz.icns'
    subprocess.run(['/usr/bin/iconutil', '-c', 'icns', '-o', str(icon), str(iconset)], check=True)
    resources.append({'source': str(icon_source), 'staged': str(icon)})
    manifest = {'distribution_info': distribution_info, 'cli': str(staged_cli), 'library': str(final), 'immutable_copy': str(staged),
                'abi_header_sha256': abi_header_sha256,
                'ui_library_sha256': hashlib.sha256(staged.read_bytes()).hexdigest(),
                'previous': str(previous) if previous else None,
                'resources_and_frameworks': resources, 'command': command,
                'signed': False, 'packaged': False, 'cache_from': cache_from,
                'remaining': 'Install resources/frameworks into the final signed app using an explicit runtime bundle lookup contract.'}
    with (run / 'artifacts/build.json').open('x') as stream:
        json.dump(manifest, stream, indent=2)
    print(json.dumps(manifest, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--generate-only', action='store_true')
    mode.add_argument('--build', action='store_true')
    parser.add_argument('--jobs', type=int, choices=(1, 2), default=2)
    parser.add_argument('--resume-run', help='Reuse an incomplete run basename, preserving its outputs')
    parser.add_argument('--cache-from', help='Clone DerivedData and SourcePackages from a completed run basename')
    parser.add_argument('--guarded', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.resume_run and args.cache_from:
        parser.error('--resume-run and --cache-from cannot be combined')
    for option, name in (('--resume-run', args.resume_run), ('--cache-from', args.cache_from)):
        if name is None:
            continue
        if not args.build or not name or name in ('.', '..') or '/' in name or '\\' in name or '\0' in name:
            parser.error(f'{option} requires --build and a single run basename')
    if not args.build:
        if args.guarded:
            parser.error('--guarded requires --build')
        generate()
    elif not args.guarded:
        subprocess.run([PYTHON, str(HERE.parent / 'cef/run-build.py'), '--', PYTHON,
                        str(Path(__file__).resolve()), '--build', '--guarded',
                        '--jobs', str(args.jobs)] + (['--resume-run', args.resume_run] if args.resume_run else []) +
                       (['--cache-from', args.cache_from] if args.cache_from else []), check=True)
    else:
        build(args.jobs, args.resume_run, args.cache_from)

if __name__ == '__main__':
    main()
