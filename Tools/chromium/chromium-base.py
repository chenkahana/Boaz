#!/opt/homebrew/bin/python3.12
"""Key, pack and upload the Chromium base that GitHub's release workflow builds the Mac app on.

GitHub-hosted runners can't build Chromium. After a Chromium change, build it here as usual (apply-patches.py,
install-host.py, build.py --build), then run `chromium-base.py pack --upload` from the same clean checkout. The
release workflow downloads the base for its commit's key and stops if it isn't uploaded.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
ROOT = Path('/Volumes/BoazBuild/cef/direct')
REPOSITORY = 'chenkahana/Boaz'
ASSET = 'chromium-base.tar.gz'
# Everything the native build reads from the repository: pins, patches, host sources, the content-blocking crate
# and its assets, and the build scripts that choose targets and arguments.
INPUTS = ['Tools/chromium/host', 'Tools/chromium/patches', 'Tools/chromium/adblock',
          'Tools/chromium/source.lock.json', 'Tools/chromium/patches.lock.json',
          'Tools/chromium/toolchains.lock.json', 'Tools/chromium/development.json',
          'Tools/chromium/build.py', 'Tools/chromium/build-adblock.py']


def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args], text=True)


def key():
    """A digest of the committed Chromium inputs at HEAD."""
    return hashlib.sha256(git('ls-tree', '-r', 'HEAD', '--', *INPUTS).encode()).hexdigest()[:16]


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def contents():
    """The base's paths under ROOT, after checking that the completed build matches this checkout."""
    if git('status', '--porcelain', '--', *INPUTS):
        raise RuntimeError('Chromium inputs have uncommitted changes; the key would not describe the base')
    native = json.loads((ROOT / 'native-built.json').read_text())
    host = {str(path.relative_to(HERE / 'host')): sha(path) for path in (HERE / 'host').rglob('*') if path.is_file()}
    if native['host']['files'] != host:
        raise RuntimeError('The built host sources differ from this checkout; install-host.py and build.py first')
    applied = json.loads((ROOT / 'patches-applied.json').read_text())
    if applied['pending'] or applied['applied'] != json.loads((HERE / 'patches.lock.json').read_text())['patches']:
        raise RuntimeError('The built patch series differs from this checkout; apply-patches.py and build.py first')
    version = json.loads((HERE / 'source.lock.json').read_text())['chromium_version']
    output = ROOT / 'chromium/src/out/BoazDevelopment'
    framework = output / 'Chromium.app/Contents/Frameworks/Chromium Framework.framework/Versions' / version
    if sha(framework / 'Chromium Framework') != native['framework_sha256']:
        raise RuntimeError('Chromium.app differs from its completed build receipt')
    blocking = Path(native['blocking']['library'])
    assets = json.loads((HERE / 'adblock/assets.lock.json').read_text())
    if not (sha(blocking) == native['blocking']['library_sha256'] == assets['native_library_sha256']):
        raise RuntimeError('The content-blocking library differs from its receipt or the asset lock')
    paths = [ROOT / 'native-built.json', output / 'Chromium.app', output / 'Chromium Packaging', blocking,
             Path(assets['artifact_directory'])]
    for path in paths:
        if path.resolve() != path or not path.is_relative_to(ROOT) or not path.exists():
            raise RuntimeError(f'Base input is missing or outside {ROOT}: {path}')
    return [str(path.relative_to(ROOT)) for path in paths]


def pack(directory, upload):
    tag = 'chromium-base-' + key()
    archive = directory / ASSET
    if archive.exists():
        raise RuntimeError(f'Refusing to overwrite {archive}')
    directory.mkdir(parents=True, exist_ok=True)
    subprocess.run(['/usr/bin/tar', '--no-mac-metadata', '-czf', str(archive), '-C', str(ROOT), *contents()], check=True)
    (directory / (ASSET + '.sha256')).write_text(f'{sha(archive)}  {ASSET}\n')
    print(f'{tag}: {archive}')
    if upload:
        # A prerelease never becomes releases/latest, which must stay the app release Sparkle reads.
        subprocess.run(['gh', 'release', 'create', tag, '--repo', REPOSITORY, '--target', git('rev-parse', 'HEAD').strip(),
                        '--prerelease', '--latest=false', '--title', f'Chromium base {key()}',
                        '--notes', 'Chromium build inputs for the Mac release workflow. Not an app release.',
                        str(archive), str(archive) + '.sha256'], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('key', help='Print the release tag of the Chromium base for HEAD')
    packing = commands.add_parser('pack', help='Archive the completed Chromium build on /Volumes/BoazBuild')
    packing.add_argument('--output', type=Path, default=REPO / 'build/chromium-base')
    packing.add_argument('--upload', action='store_true', help='Publish it as a GitHub prerelease')
    args = parser.parse_args()
    if args.command == 'key':
        print('chromium-base-' + key())
    else:
        pack(args.output.resolve(), args.upload)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f'Chromium base: {error}')
