#!/opt/homebrew/bin/python3.12
"""Package an already production-signed, notarized Boaz app without publishing."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path('/Volumes/BoazBuild/cef/direct')
HERE = Path(__file__).resolve().parent


def run(*command):
    result = subprocess.run(command, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(f'{Path(command[0]).name} verification or packaging failed')
    return result.stdout, result.stderr


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def inventory(app):
    entries = []
    for directory, dirs, files in os.walk(app, followlinks=False):
        for name in sorted(dirs + files):
            path = Path(directory) / name
            relative = str(path.relative_to(app))
            if path.is_symlink():
                resolved = path.resolve(strict=True)
                if not resolved.is_relative_to(app):
                    raise RuntimeError('Application contains an escaping symlink')
                entries.append({'path': relative, 'symlink': os.readlink(path)})
            elif path.is_file():
                entries.append({'path': relative, 'sha256': digest(path), 'size': path.stat().st_size})
            elif not path.is_dir():
                raise RuntimeError('Application contains an unsupported filesystem entry')
    return sorted(entries, key=lambda entry: entry['path'])


def package(args):
    app, output, sparkle = map(Path, (args.chromium_app, args.output, args.sparkle_bin))
    for path in (app, output, sparkle):
        if not path.is_absolute() or path.resolve() != path:
            raise RuntimeError('Paths must be absolute and canonical')
    if not output.is_relative_to(ROOT / 'artifacts') or output == ROOT / 'artifacts':
        raise RuntimeError('Output must be a new unpublished artifact directory')
    if output.exists() or output.is_symlink() or output.is_relative_to(app):
        raise RuntimeError('Refusing existing output or output inside application')
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    expected = {'CFBundleIdentifier': 'com.chenkahana.boaz', 'BoazNativeApplication': True,
                'BoazDistributionChannel': 'production', 'CrProductDirName': 'Boaz/Chromium',
                'CFBundleShortVersionString': args.version}
    if any(info.get(key) != value for key, value in expected.items()):
        raise RuntimeError('Application is not the requested production Boaz version')
    build = str(info.get('CFBundleVersion', ''))
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', build):
        raise RuntimeError('Application has an invalid numeric build version')
    executable = info.get('CFBundleExecutable', '')
    if not executable or Path(executable).name != executable:
        raise RuntimeError('Invalid application executable')
    required = ['Contents/Frameworks/libBoazApplicationUI.dylib',
                'Contents/Resources/BoazResources.bundle', 'Contents/Frameworks/Sparkle.framework',
                'Contents/Frameworks/Chromium Framework.framework', 'Contents/MacOS/boaz',
                f'Contents/MacOS/{executable}']
    if any(not (app / name).exists() for name in required):
        raise RuntimeError('Application is missing required packaged components')
    for name in ('boaz', executable):
        if not (app / 'Contents/MacOS' / name).is_file() or not os.access(app / 'Contents/MacOS' / name, os.X_OK):
            raise RuntimeError('Required executable is unavailable')
    for tool in ('generate_keys', 'sign_update'):
        if not (sparkle / tool).is_file() or not os.access(sparkle / tool, os.X_OK):
            raise RuntimeError('Sparkle tools are unavailable')
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
    _, details = run('/usr/bin/codesign', '-dv', '--verbose=4', str(app))
    details = details.decode('utf-8', errors='replace')
    if ('Authority=Developer ID Application:' not in details or
            'TeamIdentifier=DPF8459C2J' not in details or
            not re.search(r'flags=.*\bruntime\b', details)):
        raise RuntimeError('Developer ID team and hardened runtime verification failed')
    entitlements, _ = run('/usr/bin/codesign', '-d', '--entitlements', ':-', str(app))
    if entitlements and plistlib.loads(entitlements).get('com.apple.security.get-task-allow', False):
        raise RuntimeError('Debugging entitlement is not permitted')
    run('/usr/bin/xcrun', 'stapler', 'validate', str(app))
    run('/usr/sbin/spctl', '--assess', '--type', 'execute', str(app))
    key, _ = run(str(sparkle / 'generate_keys'), '-p')
    if not info.get('SUPublicEDKey') or key.decode().strip() != info['SUPublicEDKey']:
        raise RuntimeError('Application Sparkle public key does not match signing key')
    before = inventory(app)
    output.mkdir(parents=True)
    receipt = {'version': args.version, 'build': build, 'source': str(app), 'published': False,
               'source_inventory': before, 'tools': {name: {'path': str(sparkle / name),
                   'sha256': digest(sparkle / name)} for name in ('generate_keys', 'sign_update')},
               'verification': ['deep-strict-signatures', 'Developer-ID-DPF8459C2J', 'hardened-runtime',
                                'no-get-task-allow', 'staple-valid', 'gatekeeper-approved', 'Sparkle-key-match'],
               'required_gates': ['product-parity', 'DRM-playback', 'migration', 'private-profile-isolation',
                   'performance-budgets', 'signed-clean-account-launch', 'Sparkle-upgrade',
                   'last-three-version-deltas-at-most-40MiB', 'higher-version-WebKit-rollback',
                   'three-day-dogfooding-no-P0-P1'], 'complete': False}
    receipt_path = output / 'candidate-receipt.json'
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    staging = output / 'dmg'
    staging.mkdir()
    run('/usr/bin/ditto', str(app), str(staging / 'Boaz.app'))
    if inventory(staging / 'Boaz.app') != before or inventory(app) != before:
        raise RuntimeError('Application changed during packaging')
    (staging / 'Applications').symlink_to('/Applications')
    dmg = output / 'Boaz.dmg'
    run('/usr/bin/hdiutil', 'create', '-volname', 'Boaz', '-srcfolder', str(staging),
        '-fs', 'HFS+', '-format', 'UDZO', str(dmg))
    size = dmg.stat().st_size
    if size > 160 * 1024 * 1024:
        raise RuntimeError('Compressed DMG exceeds 160 MiB; artifacts preserved')
    sha = digest(dmg)
    (output / 'Boaz.dmg.sha256').write_text(f'{sha}  Boaz.dmg\n')
    signature, _ = run(str(sparkle / 'sign_update'), '-p', str(dmg))
    namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
    ET.register_namespace('sparkle', namespace)
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'Boaz candidate'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'Boaz {args.version}'
    ET.SubElement(item, f'{{{namespace}}}version').text = build
    ET.SubElement(item, f'{{{namespace}}}shortVersionString').text = args.version
    ET.SubElement(item, 'enclosure', {'url': dmg.as_uri(), 'length': str(size),
        'type': 'application/octet-stream', f'{{{namespace}}}edSignature': signature.decode().strip()})
    ET.ElementTree(rss).write(output / 'candidate-appcast.xml', encoding='utf-8', xml_declaration=True)
    receipt.update({'complete': True, 'dmg_sha256': sha, 'dmg_bytes': size,
                    'candidate_appcast': str(output / 'candidate-appcast.xml')})
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version')
    parser.add_argument('--chromium-app', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--sparkle-bin', required=True)
    parser.add_argument('--no-publish', required=True, action='store_true')
    parser.add_argument('--guarded', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', args.version):
        parser.error('VERSION must be numeric, with up to three components')
    if not args.guarded:
        return subprocess.call(['/opt/homebrew/bin/python3.12', str(HERE.parent / 'cef/run-build.py'), '--',
            '/opt/homebrew/bin/python3.12', str(Path(__file__).resolve()), *sys.argv[1:], '--guarded'])
    if Path.cwd() != ROOT.parent or os.environ.get('TMPDIR') != str(ROOT.parent / 'tmp'):
        raise RuntimeError('Packaging requires the verified SSD guard')
    with (ROOT.parent / '.build.lock').open('r') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise RuntimeError('Build guard is not holding its lock')
    package(args)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print(f'Candidate packaging failed: {error}', file=sys.stderr)
        sys.exit(1)
