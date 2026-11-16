#!/opt/homebrew/bin/python3.12
"""Install the release workflow's Developer ID identity and provisioning profile, or delete the profile afterwards.

The private key comes from a secret; the certificate comes from the App Store Connect API with the team key
(BOAZ_ASC_KEY_PATH, BOAZ_ASC_KEY_ID, BOAZ_ASC_ISSUER_ID), as does a per-run profile granting Boaz's iCloud and push
entitlements, which sign-production-application.py embeds. The workflow deletes that profile when the run ends.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = 'https://api.appstoreconnect.apple.com/v1/'
BUNDLE_ID = 'com.chenkahana.boaz'
# Profiles named with this prefix belong to the workflow; a run deletes any that an earlier run left behind.
MARKER = 'Boaz release workflow '


def encode(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=')


def token():
    """An ES256 JWT for the team key, signed with openssl and converted from DER to the raw r||s JWS form."""
    header = {'alg': 'ES256', 'kid': os.environ['BOAZ_ASC_KEY_ID'], 'typ': 'JWT'}
    now = int(time.time())
    claims = {'iss': os.environ['BOAZ_ASC_ISSUER_ID'], 'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'}
    signed = encode(json.dumps(header).encode()) + b'.' + encode(json.dumps(claims).encode())
    der = subprocess.run(['/usr/bin/openssl', 'dgst', '-sha256', '-sign', os.environ['BOAZ_ASC_KEY_PATH']],
                         input=signed, capture_output=True, check=True).stdout
    # SEQUENCE { INTEGER r, INTEGER s }, each at most 33 bytes, so every length fits in one byte.
    if der[0] != 0x30 or der[2] != 0x02:
        raise RuntimeError('Unexpected ECDSA signature encoding')
    r_end = 4 + der[3]
    r, s = der[4:r_end], der[r_end + 2:r_end + 2 + der[r_end + 1]]
    raw = b''.join(value.lstrip(b'\0').rjust(32, b'\0') for value in (r, s))
    return (signed + b'.' + encode(raw)).decode()


def request(method, path, body=None, **query):
    url = API + path + ('?' + urllib.parse.urlencode(query) if query else '')
    data = json.dumps(body).encode() if body is not None else None
    call = urllib.request.Request(url, data=data, method=method, headers={
        'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'})
    with urllib.request.urlopen(call, timeout=60) as response:
        content = response.read()
    return json.loads(content) if content else None


def openssl(*args, data=None):
    return subprocess.run(['/usr/bin/openssl', *args], input=data, capture_output=True, check=True).stdout


def install(key, certificate_id, keychain, profile, state):
    """Imports the Developer ID identity into `keychain` and writes this run's provisioning profile to `profile`."""
    certificate = request('GET', 'certificates/' + certificate_id)['data']['attributes']
    if certificate.get('certificateType') != 'DEVELOPER_ID_APPLICATION':
        raise RuntimeError(f'Certificate {certificate_id} is not a Developer ID Application certificate')
    pem = openssl('x509', '-inform', 'DER', data=base64.b64decode(certificate['certificateContent']))
    if openssl('x509', '-noout', '-pubkey', data=pem) != openssl('pkey', '-in', str(key), '-pubout'):
        raise RuntimeError(f'DEVELOPER_ID_KEY is not the private key of certificate {certificate_id}')
    state.mkdir(parents=True, exist_ok=True)
    cer, p12 = state / 'developer-id.pem', state / 'developer-id.p12'
    cer.write_bytes(pem)
    password = base64.b16encode(os.urandom(16)).decode()
    # LibreSSL's PKCS#12 defaults (3DES key bag, SHA-1 MAC) are what `security import` reads.
    openssl('pkcs12', '-export', '-inkey', str(key), '-in', str(cer), '-out', str(p12), '-passout', 'pass:' + password)
    try:
        subprocess.run(['/usr/bin/security', 'import', str(p12), '-k', keychain, '-P', password,
                        '-T', '/usr/bin/codesign'], check=True)
    finally:
        p12.unlink()
    bundles = request('GET', 'bundleIds', limit=200, **{'filter[identifier]': BUNDLE_ID})
    bundle = [item['id'] for item in bundles['data'] if item['attributes']['identifier'] == BUNDLE_ID]
    if len(bundle) != 1:
        raise RuntimeError(f'Expected one App ID {BUNDLE_ID}')
    profiles = request('GET', 'profiles', limit=200, **{'filter[profileType]': 'MAC_APP_DIRECT'})
    for item in profiles['data']:
        if item['attributes']['name'].startswith(MARKER):
            print(f'Deleting the earlier run\'s profile {item["attributes"]["name"]}')
            request('DELETE', 'profiles/' + item['id'])
    name = MARKER + os.environ.get('GITHUB_RUN_ID', 'local') + '-' + os.environ.get('GITHUB_RUN_ATTEMPT', '1')
    created = request('POST', 'profiles', {'data': {
        'type': 'profiles', 'attributes': {'name': name, 'profileType': 'MAC_APP_DIRECT'},
        'relationships': {'bundleId': {'data': {'type': 'bundleIds', 'id': bundle[0]}},
                          'certificates': {'data': [{'type': 'certificates', 'id': certificate_id}]}}}})
    (state / 'profile-id').write_text(created['data']['id'])
    profile.write_bytes(base64.b64decode(created['data']['attributes']['profileContent']))
    print(f'Installed Developer ID certificate {certificate_id} and created provisioning profile {name}')


def delete(state):
    record = state / 'profile-id'
    if not record.is_file():
        print('No provisioning profile to delete')
        return
    request('DELETE', 'profiles/' + record.read_text().strip())
    record.unlink()
    print('Deleted the run\'s provisioning profile')


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('command', choices=('install', 'delete'))
    parser.add_argument('--state', type=Path, required=True, help='Directory holding the profile ID between steps')
    parser.add_argument('--key', type=Path, help='Developer ID private key, PEM (install)')
    parser.add_argument('--certificate-id', help='App Store Connect ID of the Developer ID certificate (install)')
    parser.add_argument('--keychain', help='Keychain to import the identity into (install)')
    parser.add_argument('--profile', type=Path, help='Where to write the .provisionprofile (install)')
    args = parser.parse_args()
    if args.command == 'install':
        if not (args.key and args.certificate_id and args.keychain and args.profile):
            parser.error('install requires --key, --certificate-id, --keychain and --profile')
        install(args.key, args.certificate_id, args.keychain, args.profile, args.state)
    else:
        delete(args.state)


if __name__ == '__main__':
    try:
        main()
    except urllib.error.HTTPError as error:
        sys.exit(f'App Store Connect: {error.code} {error.read().decode(errors="replace")}')
    except (RuntimeError, OSError, KeyError, IndexError, subprocess.CalledProcessError) as error:
        sys.exit(f'Signing setup: {error}')
