#!/opt/homebrew/bin/python3.12
"""Sign and notarize a copied production assembly; never publish it."""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path('/Volumes/BoazBuild/cef/direct')
HERE = Path(__file__).resolve().parent


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def execute(command, log, capture=False):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    log.write(result.stdout if not capture else b'')
    log.write(result.stderr)
    log.flush()
    if result.returncode:
        raise RuntimeError(f'{Path(command[0]).name} failed; preserved signing log contains details')
    return result.stdout, result.stderr


def sign(args):
    source, output = Path(args.input), Path(args.output)
    for path in (source, output):
        if not path.is_absolute() or path.resolve() != path or not path.is_relative_to(ROOT / 'artifacts'):
            raise RuntimeError('Input and output must be canonical unpublished artifact paths')
    if output.exists() or output.is_symlink() or output.is_relative_to(source):
        raise RuntimeError('Output must be new and outside input')
    app = source / 'Boaz.app'
    assembly = source / 'Boaz.assembly.json'
    record = json.loads(assembly.read_text())
    if record.get('application') != str(app) or record.get('production_metadata') is not True:
        raise RuntimeError('Receipt does not identify this production assembly')
    with (app / 'Contents/Info.plist').open('rb') as stream:
        metadata = plistlib.load(stream)
    expected = {'CFBundleIdentifier': 'com.chenkahana.boaz', 'BoazNativeApplication': True,
                'BoazDistributionChannel': 'production', 'CrProductDirName': 'Boaz/Chromium'}
    if any(metadata.get(key) != value for key, value in expected.items()):
        raise RuntimeError('Production metadata is required')
    version = metadata.get('CFBundleShortVersionString', '')
    build = str(metadata.get('CFBundleVersion', ''))
    if not isinstance(version, str) or not all(re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', item) for item in (version, build)):
        raise RuntimeError('Production version and build must be numeric')
    library = app / 'Contents/Frameworks/libBoazApplicationUI.dylib'
    if sha(library) != record.get('ui_sha256'):
        raise RuntimeError('UI library does not match assembly receipt')
    profile = Path(args.provisioning_profile)
    if not profile.is_absolute() or profile.resolve() != profile or not profile.is_file():
        raise RuntimeError('A canonical Boaz Developer ID provisioning profile is required')
    decoded = subprocess.run(['/usr/bin/security', 'cms', '-D', '-i', str(profile)],
                             capture_output=True, check=True)
    provision = plistlib.loads(decoded.stdout)
    grants = provision.get('Entitlements', {})
    expiry = provision.get('ExpirationDate')
    if (provision.get('TeamIdentifier') != ['DPF8459C2J'] or not isinstance(expiry, datetime.datetime)
            or expiry.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc)
            or grants.get('com.apple.application-identifier') != 'DPF8459C2J.com.chenkahana.boaz'
            or grants.get('com.apple.security.get-task-allow', False)
            or provision.get('ProvisionsAllDevices') is not True):
        raise RuntimeError('Profile must authorize current Developer ID distribution of Boaz')
    cloud = {
        'com.apple.application-identifier': 'DPF8459C2J.com.chenkahana.boaz',
        'com.apple.developer.team-identifier': 'DPF8459C2J',
        'com.apple.developer.icloud-services': ['CloudKit'],
        'com.apple.developer.icloud-container-identifiers': ['iCloud.com.chenkahana.boaz'],
        'com.apple.developer.icloud-container-environment': 'Production',
        'com.apple.developer.aps-environment': 'production',
    }
    for key, expected_value in cloud.items():
        granted = grants.get(key)
        if isinstance(expected_value, list):
            allowed = isinstance(granted, list) and all(item in granted for item in expected_value)
        else:
            allowed = granted == expected_value or (isinstance(granted, list) and expected_value in granted)
        if not allowed:
            raise RuntimeError(f'Provisioning profile does not authorize required Boaz entitlement: {key}')
    output.mkdir(parents=True)
    work = output / 'signing-input'
    work.mkdir()
    signed_output = output / 'signed'
    signed_output.mkdir()
    receipt = {'source': str(app), 'assembly_sha256': sha(assembly), 'version': version,
               'build': build, 'published': False, 'notarized': False, 'signing_complete': False}
    receipt_path = output / 'production-signing.json'
    with (output / 'sign.log').open('xb') as log:
        execute(['/usr/bin/ditto', '--clone', str(app), str(work / 'Boaz.app')], log)
        packaging = work / 'Chromium Packaging'
        shutil.copytree(ROOT / 'chromium/src/out/BoazDevelopment/Chromium Packaging', packaging,
                        symlinks=True, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        shutil.copy2(profile, packaging / 'Boaz.provisionprofile')
        browser_entitlements = packaging / 'app-entitlements.plist'
        with browser_entitlements.open('rb') as stream:
            entitlements = plistlib.load(stream)
        entitlements.update(cloud)
        browser_entitlements.write_bytes(plistlib.dumps(entitlements))
        config = packaging / 'signing/internal_config.py'
        if config.exists() or config.is_symlink():
            raise RuntimeError('Unexpected upstream internal signing configuration')
        config.write_text('from signing.chromium_config import ChromiumCodeSignConfig\n\n'
            'class InternalCodeSignConfig(ChromiumCodeSignConfig):\n'
            '    @property\n    def app_product(self): return "Boaz"\n'
            '    @property\n    def product(self): return "Chromium"\n'
            '    @property\n    def provisioning_profile_basename(self): return "Boaz"\n'
            f'    @property\n    def version(self): return {version!r}\n'
            '    @property\n    def base_bundle_id(self): return "com.chenkahana.boaz"\n')
        signer = packaging / 'signing/signing.py'
        original = signer.read_text()
        anchor = """        if config.notarize.should_notarize():
            # If the products will be notarized, the signature requires a secure
            # timestamp.
            command.append('--timestamp')
"""
        if original.count(anchor) != 1:
            raise RuntimeError('Pinned timestamp signing anchor changed')
        before = sha(signer)
        signer.write_text(original.replace(anchor, "        command.append('--timestamp')\n"))
        receipt['timestamp_patch'] = {'before_sha256': before, 'after_sha256': sha(signer)}
        receipt['config_sha256'] = sha(config)
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
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
            command = ['/usr/bin/codesign', '--force', '--sign', args.identity, '--timestamp',
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
        _, details = execute(['/usr/bin/codesign', '-dv', '--verbose=4', str(signed_app)], log)
        details = details.decode(errors='replace')
        if ('Authority=Developer ID Application:' not in details or 'TeamIdentifier=DPF8459C2J' not in details
                or not re.search(r'flags=.*\bruntime\b', details) or 'Timestamp=' not in details):
            raise RuntimeError('Production identity, hardened runtime or secure timestamp verification failed')
        bundles = [signed_app] + [p for p in signed_app.rglob('*') if p.suffix in ('.app', '.xpc') and not p.is_symlink()]
        for bundle in bundles:
            entitlements, _ = execute(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(bundle)], log, capture=True)
            if entitlements and plistlib.loads(entitlements).get('com.apple.security.get-task-allow', False):
                raise RuntimeError('Debugging entitlement found in signed product')
        browser_signed, _ = execute(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(signed_app)], log, capture=True)
        signed_entitlements = plistlib.loads(browser_signed)
        if any(signed_entitlements.get(key) != value for key, value in cloud.items()):
            raise RuntimeError('Signed browser does not preserve required Boaz iCloud entitlements')
        if sha(signed_app / 'Contents/embedded.provisionprofile') != sha(profile):
            raise RuntimeError('Signed browser provisioning profile differs')
        archive = output / 'Boaz-notarization.zip'
        execute(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(signed_app), str(archive)], log)
        reply, _ = execute(['/usr/bin/xcrun', 'notarytool', 'submit', str(archive),
                    '--keychain-profile', args.notary_profile, '--wait', '--output-format', 'json'], log, capture=True)
        notarization = json.loads(reply)
        (output / 'notarization.json').write_text(json.dumps(notarization, indent=2) + '\n')
        if notarization.get('status') != 'Accepted':
            raise RuntimeError('Apple did not accept this candidate')
        execute(['/usr/bin/xcrun', 'stapler', 'staple', str(signed_app)], log)
        execute(['/usr/bin/xcrun', 'stapler', 'validate', str(signed_app)], log)
        execute(['/usr/sbin/spctl', '--assess', '--type', 'execute', str(signed_app)], log)
        receipt.update({'application': str(signed_app), 'notarized': True, 'signing_complete': True,
                        'notarization_id': notarization.get('id'), 'production_ready': False})
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('input', 'output', 'identity', 'notary-profile', 'provisioning-profile'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--guarded', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not args.guarded:
        return subprocess.call(['/opt/homebrew/bin/python3.12', str(HERE.parent / 'cef/run-build.py'), '--',
            '/opt/homebrew/bin/python3.12', str(Path(__file__).resolve()), *sys.argv[1:], '--guarded'])
    if Path.cwd() != ROOT.parent or os.environ.get('TMPDIR') != str(ROOT.parent / 'tmp'):
        raise RuntimeError('Signing requires the verified SSD guard')
    with (ROOT.parent / '.build.lock').open('r') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise RuntimeError('Build guard is not holding its lock')
    sign(args)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print(f'Production signing failed: {error}', file=sys.stderr)
        sys.exit(1)
