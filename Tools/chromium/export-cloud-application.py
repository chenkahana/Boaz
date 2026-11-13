#!/opt/homebrew/bin/python3.12
"""Unpublished archive/cloud-export experiment. Never a production signing receipt."""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import selectors
import subprocess
import sys

ROOT = Path('/Volumes/BoazBuild/cef/direct')
HERE = Path(__file__).resolve().parent
PYTHON = '/opt/homebrew/bin/python3.12'
TEAM = 'DPF8459C2J'


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def execute(command, log, capture=False):
    # Drain all output, retaining at most 8 MiB per command; never print values.
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    buffers = [bytearray(), bytearray()]
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ, 0)
        selector.register(process.stderr, selectors.EVENT_READ, 1)
        while selector.get_map():
            for key, _ in selector.select():
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                kept = buffers[key.data]
                kept.extend(chunk[:max(0, 8 * 1024 * 1024 - len(kept))])
    status = process.wait()
    if not capture:
        log.write(buffers[0])
    log.write(buffers[1])
    log.flush()
    if status:
        raise RuntimeError(f'{Path(command[0]).name} failed; preserved experiment log contains details')
    return bytes(buffers[0]), bytes(buffers[1])


def experiment(args):
    source, output = Path(args.input), Path(args.output)
    for path in (source, output):
        if not path.is_absolute() or path.resolve() != path or not path.is_relative_to(ROOT / 'artifacts'):
            raise RuntimeError('Canonical unpublished artifact paths required')
    if output.exists() or output.is_symlink() or output.is_relative_to(source):
        raise RuntimeError('Output must be new and outside input')
    if not args.identity.startswith('Apple Development:'):
        raise RuntimeError('An existing Apple Development signing identity is required for this archive experiment')
    app = source / 'Boaz.app'
    assembly = source / 'Boaz.assembly.json'
    record = json.loads(assembly.read_text())
    metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if (record.get('application') != str(app) or record.get('production_metadata') is not True
            or metadata.get('CFBundleIdentifier') != 'com.chenkahana.boaz'
            or metadata.get('BoazDistributionChannel') != 'production'
            or metadata.get('BoazNativeApplication') is not True):
        raise RuntimeError('Verified production assembly required')
    if sha(app / 'Contents/Frameworks/libBoazApplicationUI.dylib') != record.get('ui_sha256'):
        raise RuntimeError('UI library differs from assembly receipt')
    version = metadata['CFBundleShortVersionString']
    output.mkdir(parents=True)
    work = output / 'archive-signing-input'
    work.mkdir()
    signed_output = output / 'archive-signed'
    signed_output.mkdir()
    receipt_path = output / 'cloud-export-experiment.json'
    receipt = {'published': False, 'verified': False, 'production_usable': False,
               'assembly_sha256': sha(assembly), 'export_attempted': False, 'export_succeeded': False}
    receipt_path.write_text(json.dumps(receipt, indent=2))
    with (output / 'experiment.log').open('xb') as log:
        execute(['/usr/bin/ditto', '--clone', str(app), str(work / 'Boaz.app')], log)
        packaging = work / 'Chromium Packaging'
        shutil.copytree(ROOT / 'chromium/src/out/BoazDevelopment/Chromium Packaging', packaging,
                        symlinks=True, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        entitlements_path = packaging / 'app-entitlements.plist'
        entitlements = plistlib.loads(entitlements_path.read_bytes())
        entitlements.update({
            'com.apple.application-identifier': TEAM + '.com.chenkahana.boaz',
            'com.apple.developer.team-identifier': TEAM,
            'com.apple.developer.icloud-services': ['CloudKit'],
            'com.apple.developer.icloud-container-identifiers': ['iCloud.com.chenkahana.boaz'],
            'com.apple.developer.icloud-container-environment': 'Production',
            'com.apple.developer.aps-environment': 'production',
        })
        entitlements_path.write_bytes(plistlib.dumps(entitlements))
        config = packaging / 'signing/internal_config.py'
        if config.exists() or config.is_symlink():
            raise RuntimeError('Unexpected upstream internal configuration')
        # Development-signed archive input cannot pass distribution Gatekeeper.
        # Exported output remains unverified until independent production checks.
        config.write_text('from signing.chromium_config import ChromiumCodeSignConfig\n\n'
            'class InternalCodeSignConfig(ChromiumCodeSignConfig):\n'
            '    @property\n    def app_product(self): return "Boaz"\n'
            '    @property\n    def product(self): return "Chromium"\n'
            '    @property\n    def base_bundle_id(self): return "com.chenkahana.boaz"\n'
            '    @property\n    def run_spctl_assess(self): return False\n'
            f'    @property\n    def version(self): return {version!r}\n')
        copied_app = work / 'Boaz.app'
        sparkle = copied_app / 'Contents/Frameworks/Sparkle.framework'
        if not sparkle.is_dir():
            raise RuntimeError('Sparkle framework is missing')
        targets = []
        for path in sparkle.rglob('*'):
            if path.is_symlink() or not path.is_file():
                continue
            with path.open('rb') as stream:
                magic = stream.read(4)
            if magic in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf'):
                targets.append(path)
        targets += sorted((p for p in sparkle.rglob('*') if p.suffix in ('.app', '.xpc') and not p.is_symlink()),
                          key=lambda p: len(p.parts), reverse=True)
        targets += [sparkle, copied_app / 'Contents/Frameworks/libBoazApplicationUI.dylib',
                    copied_app / 'Contents/Frameworks/libboaz_adblock.dylib',
                    copied_app / 'Contents/MacOS/boaz']
        # Capture before any inner executable is re-signed: a bundle and its
        # executable share their signature, including service entitlements.
        preserved_entitlements = {}
        entitlement_dir = output / 'sparkle-entitlements'
        entitlement_dir.mkdir()
        for index, target in enumerate(targets):
            if not target.is_relative_to(sparkle):
                continue
            raw, _ = execute(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(target)], log, capture=True)
            values = plistlib.loads(raw) if raw else {}
            if values.get('com.apple.security.get-task-allow', False):
                raise RuntimeError('Sparkle contains a debugging entitlement')
            path = entitlement_dir / f'{index}.plist'
            path.write_bytes(plistlib.dumps(values))
            preserved_entitlements[target] = (path, values)
        receipt['sparkle_entitlements'] = {
            str(target.relative_to(copied_app)): values
            for target, (_, values) in preserved_entitlements.items()}
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
        for target in targets:
            if not target.exists():
                raise RuntimeError('Required Boaz signing component is missing')
            command = ['/usr/bin/codesign', '--force', '--sign', args.identity, 
                       '--options', 'runtime', '--preserve-metadata=identifier']
            if target in preserved_entitlements:
                command += ['--entitlements', str(preserved_entitlements[target][0])]
            execute([*command, str(target)], log)
        for target, (_, expected_entitlements) in preserved_entitlements.items():
            raw, _ = execute(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(target)], log, capture=True)
            if (plistlib.loads(raw) if raw else {}) != expected_entitlements:
                raise RuntimeError('Sparkle entitlements changed during signing')
        execute(['/opt/homebrew/bin/python3.12', str(packaging / 'sign_chrome.py'),
                 '--identity', args.identity, '--input', str(work), '--output', str(signed_output),
                 '--channel', 'stable', '--disable-packaging', '--notarize', 'none'], log)
        signed_app = signed_output / 'stable/Boaz.app'
        execute(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(signed_app)], log)
        archive = output / 'Boaz.xcarchive'
        archive_app = archive / 'Products/Applications/Boaz.app'
        execute(['/usr/bin/ditto', '--clone', str(signed_app), str(archive_app)], log)
        archive_info = {'ArchiveVersion': 2, 'Name': 'Boaz', 'SchemeName': 'Boaz',
            'CreationDate': datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
            'ApplicationProperties': {'ApplicationPath': 'Applications/Boaz.app',
                'CFBundleIdentifier': 'com.chenkahana.boaz', 'CFBundleShortVersionString': version,
                'CFBundleVersion': metadata['CFBundleVersion'], 'SigningIdentity': args.identity,
                'Team': TEAM}}
        (archive / 'Info.plist').write_bytes(plistlib.dumps(archive_info))
        options = output / 'ExportOptions.plist'
        options.write_bytes(plistlib.dumps({'method': 'developer-id', 'signingStyle': 'automatic',
                                           'teamID': TEAM, 'destination': 'upload'}))
        receipt['export_attempted'] = True
        receipt_path.write_text(json.dumps(receipt, indent=2))
        execute(['/usr/bin/xcodebuild', '-exportArchive', '-archivePath', str(archive),
                 '-exportPath', str(output / 'export'), '-exportOptionsPlist', str(options),
                 '-allowProvisioningUpdates'], log)
        receipt['export_succeeded'] = True
        receipt_path.write_text(json.dumps(receipt, indent=2))
    print('Cloud export attempt finished. Output remains unpublished and unverified; no notarization polling or launch performed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('input', 'output', 'identity'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--guarded', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not args.guarded:
        return subprocess.call([PYTHON, str(HERE.parent / 'cef/run-build.py'), '--',
                                PYTHON, str(Path(__file__).resolve()), *sys.argv[1:], '--guarded'])
    if Path.cwd() != ROOT.parent or os.environ.get('TMPDIR') != str(ROOT.parent / 'tmp'):
        raise RuntimeError('Verified SSD guard required')
    with (ROOT.parent / '.build.lock').open() as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise RuntimeError('Build guard does not hold its lock')
    experiment(args)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print(f'Cloud export experiment failed: {error}', file=sys.stderr)
        sys.exit(1)
