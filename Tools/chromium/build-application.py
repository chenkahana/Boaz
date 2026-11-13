#!/opt/homebrew/bin/python3.12
"""Generate or explicitly build the native Boaz UI library without publishing."""
import argparse
import datetime
import fcntl
import json
import os
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


def build(jobs):
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
    run = APP / 'runs' / stamp
    if run.resolve() != run:
        raise RuntimeError('Application run directory is redirected')
    run.mkdir(parents=True)
    for name in ('tmp', 'cache', 'artifacts'):
        (run / name).mkdir()
    env = dict(os.environ, TMPDIR=str(run / 'tmp'), XDG_CACHE_HOME=str(run / 'cache'),
               CLANG_MODULE_CACHE_PATH=str(run / 'cache/clang'),
               SWIFT_MODULE_CACHE_PATH=str(run / 'cache/swift'))
    command = ['xcrun', 'xcodebuild', '-project', str(PROJECT / 'BoazChromiumUI.xcodeproj'),
               '-scheme', 'Boaz-ChromiumUI', '-configuration', 'Release',
               '-destination', 'generic/platform=macOS', '-jobs', str(jobs),
               '-derivedDataPath', str(run / 'DerivedData'),
               '-clonedSourcePackagesDirPath', str(run / 'SourcePackages'),
               '-resultBundlePath', str(run / 'Build.xcresult'),
               'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'build']
    print(f'Application build log: {run / "xcodebuild.log"}', flush=True)
    with (run / 'xcodebuild.log').open('x') as log:
        subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    products = run / 'DerivedData/Build/Products/Release'
    library = products / 'libBoazApplicationUI.dylib'
    if not library.is_file() or library.is_symlink():
        raise RuntimeError('Expected dynamic library was not produced')
    staged = run / 'artifacts/libBoazApplicationUI.dylib'
    shutil.copy2(library, staged)
    resources = []
    for item in sorted(products.iterdir()):
        if item.suffix not in ('.bundle', '.car', '.metallib', '.framework'):
            continue
        copied = run / 'artifacts' / item.name
        if item.is_symlink():
            raise RuntimeError(f'Unexpected top-level resource symlink: {item}')
        if item.is_dir():
            shutil.copytree(item, copied, symlinks=True)
        else:
            shutil.copy2(item, copied)
        resources.append({'source': str(item), 'staged': str(copied)})
    available(final)
    previous = None
    if final.exists():
        previous = APP / f'libBoazApplicationUI.previous-{stamp}.dylib'
        final.rename(previous)
    os.link(staged, final)
    manifest = {'library': str(final), 'immutable_copy': str(staged),
                'previous': str(previous) if previous else None,
                'resources_and_frameworks': resources, 'command': command,
                'signed': False, 'packaged': False,
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
    parser.add_argument('--guarded', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not args.build:
        if args.guarded:
            parser.error('--guarded requires --build')
        generate()
    elif not args.guarded:
        subprocess.run([PYTHON, str(HERE.parent / 'cef/run-build.py'), '--', PYTHON,
                        str(Path(__file__).resolve()), '--build', '--guarded',
                        '--jobs', str(args.jobs)], check=True)
    else:
        build(args.jobs)

if __name__ == '__main__':
    main()
