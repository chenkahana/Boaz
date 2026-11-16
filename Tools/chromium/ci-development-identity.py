#!/opt/homebrew/bin/python3.12
"""Create or revoke the per-run Apple Development certificate the release workflow signs the archive input with.

export-cloud-application.py signs with an Apple Development identity before Xcode re-signs with the cloud-managed
Developer ID certificate. A hosted runner has none, so each run creates one through the App Store Connect API with
the team key (BOAZ_ASC_KEY_PATH, BOAZ_ASC_KEY_ID, BOAZ_ASC_ISSUER_ID) and revokes it when the run ends.
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
import urllib.request

API = 'https://api.appstoreconnect.apple.com/v1/certificates'
# Apple names every certificate created with an API key this way; CI is the only thing that creates them for Boaz.
CI_MARKER = 'Created via API'


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


def request(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    call = urllib.request.Request(url, data=data, method=method, headers={
        'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'})
    with urllib.request.urlopen(call, timeout=60) as response:
        content = response.read()
    return json.loads(content) if content else None


def revoke_stale():
    listing = request('GET', API + '?filter[certificateType]=DEVELOPMENT&limit=200')
    for certificate in listing['data']:
        name = certificate['attributes'].get('name', '')
        if CI_MARKER in name:
            print(f'Revoking stale CI certificate {certificate["id"]} ({name})')
            request('DELETE', f'{API}/{certificate["id"]}')


def create(state, keychain):
    state.mkdir(parents=True, exist_ok=True)
    key, csr, cer, p12 = (state / name for name in ('key.pem', 'request.csr', 'certificate.pem', 'identity.p12'))
    subprocess.run(['/usr/bin/openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(key),
                    '-out', str(csr), '-subj', '/CN=Boaz release workflow'], check=True, capture_output=True)
    body = {'data': {'type': 'certificates', 'attributes': {
        'certificateType': 'DEVELOPMENT', 'csrContent': csr.read_text()}}}
    try:
        created = request('POST', API, body)
    except urllib.error.HTTPError as error:
        if error.code != 409:
            raise
        # Usually the certificate limit, left full by runs that ended before revoking.
        print(f'Apple refused a new certificate ({error.code}): {error.read().decode(errors="replace")}')
        revoke_stale()
        created = request('POST', API, body)
    identifier = created['data']['id']
    (state / 'certificate-id').write_text(identifier)
    der = base64.b64decode(created['data']['attributes']['certificateContent'])
    cer.write_bytes(subprocess.run(['/usr/bin/openssl', 'x509', '-inform', 'DER'], input=der,
                                   capture_output=True, check=True).stdout)
    password = base64.b16encode(os.urandom(16)).decode()
    # LibreSSL's PKCS#12 defaults (3DES, SHA-1 MAC) are what `security import` reads.
    subprocess.run(['/usr/bin/openssl', 'pkcs12', '-export', '-inkey', str(key), '-in', str(cer),
                    '-out', str(p12), '-passout', 'pass:' + password], check=True, capture_output=True)
    subprocess.run(['/usr/bin/security', 'import', str(p12), '-k', keychain, '-P', password,
                    '-T', '/usr/bin/codesign'], check=True)
    for path in (key, p12):
        path.unlink()
    print(f'Created Apple Development certificate {identifier}')


def revoke(state):
    record = state / 'certificate-id'
    if not record.is_file():
        print('No certificate to revoke')
        return
    request('DELETE', f'{API}/{record.read_text().strip()}')
    record.unlink()
    print('Revoked the run\'s Apple Development certificate')


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('command', choices=('create', 'revoke'))
    parser.add_argument('--state', type=Path, required=True, help='Directory holding the certificate ID between steps')
    parser.add_argument('--keychain', help='Keychain to import the identity into (create)')
    args = parser.parse_args()
    if args.command == 'create':
        if not args.keychain:
            parser.error('create requires --keychain')
        create(args.state, args.keychain)
    else:
        revoke(args.state)


if __name__ == '__main__':
    try:
        main()
    except urllib.error.HTTPError as error:
        sys.exit(f'App Store Connect: {error.code} {error.read().decode(errors="replace")}')
    except (RuntimeError, OSError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f'Development identity: {error}')
