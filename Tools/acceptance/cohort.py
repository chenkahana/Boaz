"""Prepares the extension cohort for row 3 part B: each extension's CRX downloaded anonymously from Google's update
service (as Chrome fetches one), checked against its store ID, unpacked, and given its store public key as
manifest `key`, so Load unpacked gives it the same ID as the store's. Standard library only.

  cohort.py <output dir> <extension id> ...    writes <output dir>/<id>/ and <output dir>/cohort.json
"""
import base64
import hashlib
import io
import json
import pathlib
import shutil
import sys
import urllib.request
import zipfile

UPDATE = ('https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx3'
          '&prodversion=140.0.0.0&x=id%3D{id}%26uc')


def varint(data, at):
    value = shift = 0
    while True:
        byte = data[at]
        at += 1
        value |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            return value, at


def fields(data):
    """(field number, bytes) for each length-delimited field of a protobuf message; others are skipped."""
    at = 0
    while at < len(data):
        key, at = varint(data, at)
        number, kind = key >> 3, key & 7
        if kind == 2:
            length, at = varint(data, at)
            yield number, data[at:at + length]
            at += length
        elif kind == 0:
            _, at = varint(data, at)
        elif kind == 1:
            at += 8
        elif kind == 5:
            at += 4
        else:
            raise ValueError(f'unsupported protobuf wire type {kind}')


def extension_id(public_key):
    return ''.join(chr(97 + int(c, 16)) for c in hashlib.sha256(public_key).hexdigest()[:32])


def unpack(crx, id):
    """The CRX3's ZIP and the public key whose ID is `id` (CrxFileHeader: proofs in fields 2 and 3)."""
    if crx[:4] != b'Cr24' or int.from_bytes(crx[4:8], 'little') != 3:
        raise ValueError('not a CRX3 file')
    length = int.from_bytes(crx[8:12], 'little')
    header = crx[12:12 + length]
    keys = [dict(fields(proof)).get(1) for number, proof in fields(header) if number in (2, 3)]
    key = next((k for k in keys if k and extension_id(k) == id), None)
    if key is None:
        raise ValueError(f'no key in the CRX matches {id}')
    return crx[12 + length:], key


def prepare(out, id):
    crx = urllib.request.urlopen(UPDATE.format(id=id), timeout=120).read()
    archive, key = unpack(crx, id)
    folder = out / id
    shutil.rmtree(folder, ignore_errors=True)
    zipfile.ZipFile(io.BytesIO(archive)).extractall(folder)
    # Names starting with "_" are reserved; the store's signature folder stops Load unpacked.
    shutil.rmtree(folder / '_metadata', ignore_errors=True)
    manifest = json.loads((folder / 'manifest.json').read_text(encoding='utf-8-sig'))
    manifest['key'] = base64.b64encode(key).decode()
    (folder / 'manifest.json').write_text(json.dumps(manifest, indent=1))
    return {'id': id, 'name': manifest.get('name'), 'version': manifest.get('version'),
            'crx_sha256': hashlib.sha256(crx).hexdigest(), 'path': str(folder)}


def main():
    out, *ids = sys.argv[1:]
    out = pathlib.Path(out)
    out.mkdir(parents=True, exist_ok=True)
    prepared = [prepare(out, id) for id in ids]
    (out / 'cohort.json').write_text(json.dumps(prepared, indent=1))
    for entry in prepared:
        print(f"{entry['id']} {entry['name']} {entry['version']} sha256 {entry['crx_sha256']}")


if __name__ == '__main__':
    main()
