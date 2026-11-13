#!/usr/bin/env python3
"""Validate pinned content-blocking inputs before creating distributable assets."""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import re
import sys

STORAGE = Path('/Volumes/BoazBuild/cef/direct')
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
MAX_INPUT = 64 * 1024 * 1024


def digest(data):
    return hashlib.sha256(data).hexdigest()


def confined(value, root, missing=False):
    path = Path(value).absolute()
    if '..' in path.parts or not path.is_relative_to(root):
        raise ValueError('Path outside approved storage')
    for part in [*reversed(path.parents), path]:
        if part.is_symlink():
            raise ValueError('Symlink path refused')
    if missing:
        if path.exists() or not path.parent.is_dir():
            raise ValueError('Output must be new with an existing parent')
    elif not path.is_file():
        raise ValueError('Input must be a regular file')
    return path


def read(path, limit=MAX_INPUT):
    if path.stat().st_size > limit:
        raise ValueError('Input exceeds size limit')
    return path.read_bytes()


def checked(path, expected, size=None):
    data = read(path)
    if digest(data) != expected or (size is not None and len(data) != size):
        raise ValueError('Input hash or size mismatch: ' + path.name)
    return data


def own_domains():
    source = REPO / 'Apps/Browser/ContentBlocking.swift'
    data = read(source)
    matches = list(re.finditer(r'private\s+static\s+let\s+domains\s*:\s*\[String\]\s*=\s*\[([^\]]*)\]', data.decode('utf-8'), re.S))
    if len(matches) != 1:
        raise ValueError('Expected exactly one literal ContentBlocking.domains array')
    body = re.sub(r'//[^\n]*', '', matches[0].group(1))
    tokens = re.findall(r'"[^"\\\n]*"|,|\s+', body)
    if ''.join(tokens) != body:
        raise ValueError('Nonliteral tracker array content')
    values = []
    expect_value = True
    for token in tokens:
        if token.isspace():
            continue
        if token == ',':
            if expect_value:
                raise ValueError('Malformed tracker array comma')
            expect_value = True
            continue
        if not expect_value:
            raise ValueError('Missing tracker array comma')
        domain = json.loads(token)
        if len(domain) > 253 or not re.fullmatch(r'[a-z0-9]+(?:[a-z0-9.-]*[a-z0-9])?', domain):
            raise ValueError('Invalid tracker domain literal')
        if any(not label or len(label) > 63 or label.startswith('-') or label.endswith('-') for label in domain.split('.')):
            raise ValueError('Invalid tracker domain label')
        values.append(domain)
        expect_value = False
    if not values:
        raise ValueError('Empty tracker domain array')
    rules = ('! Boaz tracker hosts; third-party only\n' + ''.join('||' + domain + '^$third-party\n' for domain in values)).encode()
    return rules, {'source': str(source.relative_to(REPO)), 'source_sha256': digest(data),
                   'domain_count': len(values), 'semantics': 'ABP hostname/subdomain boundary, third-party only'}


class Bytes(ctypes.Structure):
    _fields_ = [('data', ctypes.POINTER(ctypes.c_uint8)), ('len', ctypes.c_size_t)]


class Buffer(ctypes.Structure):
    _fields_ = [('data', ctypes.POINTER(ctypes.c_uint8)), ('len', ctypes.c_size_t)]


def validate_engine(library, rules, resources):
    lib = ctypes.CDLL(str(library))
    lib.boaz_adblock_create.argtypes = [Bytes, Bytes, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(Buffer)]
    lib.boaz_adblock_create.restype = ctypes.c_int32
    lib.boaz_adblock_destroy.argtypes = [ctypes.c_void_p]
    lib.boaz_adblock_destroy.restype = None
    lib.boaz_adblock_buffer_free.argtypes = [Buffer]
    lib.boaz_adblock_buffer_free.restype = None
    rule_storage = (ctypes.c_uint8 * len(rules)).from_buffer_copy(rules)
    resource_storage = (ctypes.c_uint8 * len(resources)).from_buffer_copy(resources)
    engine = ctypes.c_void_p()
    diagnostics = Buffer()
    try:
        status = lib.boaz_adblock_create(Bytes(rule_storage, len(rules)), Bytes(resource_storage, len(resources)), ctypes.byref(engine), ctypes.byref(diagnostics))
        if diagnostics.len > 1024 * 1024 or (diagnostics.len and not diagnostics.data):
            raise ValueError('Invalid native diagnostics buffer')
        detail = json.loads(ctypes.string_at(diagnostics.data, diagnostics.len)) if diagnostics.len else {}
        if status == 0 and not engine.value:
            raise ValueError('Native success without engine')
        return status, detail
    finally:
        if engine.value:
            lib.boaz_adblock_destroy(engine)
        lib.boaz_adblock_buffer_free(diagnostics)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resources', required=True, help='Pinned packaged Resource JSON; adjacent .receipt.json required')
    parser.add_argument('--build-receipt', default=str(STORAGE / 'adblock-built.json'))
    parser.add_argument('--output', required=True, help='New directory beneath /Volumes/BoazBuild/cef/direct/adblock')
    args = parser.parse_args()
    output = confined(args.output, STORAGE / 'adblock', missing=True)
    lock_bytes = read(HERE / 'lists.lock.json')
    resource_lock = read(HERE / 'resources.lock.json')
    lists = json.loads(lock_bytes)
    if lists['schema_version'] != 1 or [v['name'] for v in lists['lists']] != ['easylist', 'easyprivacy']:
        raise ValueError('Unexpected list lock schema/order')
    resource_path = confined(args.resources, STORAGE / 'adblock')
    resource_receipt_path = confined(str(resource_path) + '.receipt.json', STORAGE / 'adblock')
    resource_receipt_bytes = read(resource_receipt_path)
    resource_receipt = json.loads(resource_receipt_bytes)
    if resource_receipt['resources_lock_sha256'] != digest(resource_lock) or resource_receipt['lists_lock_sha256'] != digest(lock_bytes):
        raise ValueError('Resource receipt does not match pinned lists/resources')
    if resource_receipt['package_script_sha256'] != digest(read(HERE / 'package-resources.mjs')):
        raise ValueError('Resource packager changed since receipt')
    resources = checked(resource_path, resource_receipt['sha256'], resource_receipt['size_bytes'])
    build_bytes = read(confined(args.build_receipt, STORAGE))
    build = json.loads(build_bytes)
    if build['exit_code'] != 0:
        raise ValueError('Native blocker build failed')
    if build['header_sha256'] != digest(read(HERE.parent / 'host/boaz_adblock.h')):
        raise ValueError('Native blocker C ABI header changed')
    patch_manifest = json.loads(read(HERE / 'patches.lock.json'))
    for name in ['Cargo.toml', 'Cargo.lock', 'src/lib.rs', 'patches.lock.json',
                 *(entry['file'] for entry in patch_manifest['patches'])]:
        if build['inputs'].get(name) != digest(read(HERE / name)):
            raise ValueError('Native blocker source differs from build: ' + name)
    library = confined(build['library'], STORAGE / 'adblock')
    checked(library, build['library_sha256'])
    inputs = {}
    sections = []
    line = 1
    for item in lists['lists']:
        data = checked(confined(item['artifact_path'], STORAGE / 'adblock'), item['sha256'], item['size_bytes'])
        data.decode('utf-8')
        inputs[item['name'] + '.txt'] = data
        normalized = data if data.endswith(b'\n') else data + b'\n'
        sections.append((line, line + normalized.count(b'\n') - 1, item['name']))
        line += normalized.count(b'\n')
    own, own_provenance = own_domains()
    inputs['boaz-trackers.txt'] = own
    sections.append((line, line + own.count(b'\n') - 1, 'boaz-trackers'))
    combined = b''.join(v if v.endswith(b'\n') else v + b'\n' for v in inputs.values())
    if len(combined) > MAX_INPUT:
        raise ValueError('Combined rules exceed native input limit')
    status, detail = validate_engine(library, combined, resources)
    compatibility_bytes = read(HERE / 'compatibility.json')
    compatibility = json.loads(compatibility_bytes)
    if compatibility['lists_lock_sha256'] != digest(lock_bytes):
        raise ValueError('Subscription compatibility decisions require review for these list versions')
    exclusions = compatibility['optional_exclusions']
    if compatibility.get('schema_version') != 1 or len(exclusions) != 7:
        raise ValueError('Unexpected compatibility exclusion count')
    if (status != 4 or detail.get('rejected_rules') != 7
            or detail.get('rejected_resources') != 0
            or detail.get('rejected_rule_details_truncated') is not False
            or len(detail.get('rejected_rule_details', [])) != 7):
        raise ValueError('Unexpected subscription rejection; no exclusions applied: '
                         + json.dumps(detail))
    subscription_diagnostics = detail
    rejection_reasons = {entry['line']: entry['reason']
                         for entry in detail['rejected_rule_details']}
    if len(rejection_reasons) != 7:
        raise ValueError('Duplicate native rejected-rule indices')
    lines = combined.decode('utf-8').splitlines(keepends=True)
    excluded_indices = set()
    for entry in exclusions:
        source = next((row for row in sections if row[2] == entry['list']), None)
        if source is None or not isinstance(entry['line'], int):
            raise ValueError('Invalid compatibility source')
        number = source[0] + entry['line'] - 1
        if not source[0] <= number <= source[1] or number in excluded_indices:
            raise ValueError('Invalid or duplicate compatibility rule position')
        if (lines[number - 1].rstrip('\r\n') != entry['rule'] or
                rejection_reasons.get(number) != entry['parser_reason']):
            raise ValueError('Optional rule capability changed; review compatibility decision')
        excluded_indices.add(number)
        lines[number - 1] = '! Boaz unsupported optional rule: ' + entry['rule'] + '\n'
    if exclusions:
        combined = ''.join(lines).encode('utf-8')
        status, detail = validate_engine(library, combined, resources)
    if status != 0:
        mapped = []
        source_lines = combined.decode().splitlines()
        for number in detail.get('invalid_rule_line_numbers_sample', [])[:32]:
            if not isinstance(number, int) or not 1 <= number <= len(source_lines):
                raise ValueError('Invalid native rejected-rule index')
            for first, last, name in sections:
                if first <= number <= last:
                    mapped.append({'list': name, 'line': number - first + 1, 'rule': source_lines[number - 1][:256]})
                    break
        print(json.dumps({'status': 'rejected', 'native_status': status, 'diagnostics': detail, 'rules_sample': mapped}))
        return 1
    if detail.get('rejected_rules') != 0 or detail.get('rejected_resources') != 0:
        raise ValueError('Successful snapshot contains rejected inputs')
    for entry in json.loads(resource_lock)['files']:
        if Path(entry['path']).name not in ['LICENSE', 'LICENSE.txt']:
            continue
        filename = 'LICENSE-' + entry['repository'].replace('/', '-') + '.txt'
        inputs[filename] = checked(confined(entry['artifact_path'], STORAGE / 'adblock'),
                                   entry['sha256'], entry['size_bytes'])
    inputs.update({'rules.txt': combined, 'resources.json': resources,
                   'lists.lock.json': lock_bytes, 'resources.lock.json': resource_lock,
                   'resources.receipt.json': resource_receipt_bytes, 'compatibility.json': compatibility_bytes,
                   'NOTICE': read(HERE / 'NOTICE')})
    provenance = {'schema_version': 1, 'validation': 'native_engine_creation_passed',
                  'full_subscription_supported': not bool(exclusions),
                  'optional_excluded_rule_count': len(exclusions),
                  'native_library_sha256': build['library_sha256'], 'build_receipt_sha256': digest(build_bytes),
                  'tracker_source': own_provenance, 'diagnostics': detail,
                  'original_subscription_diagnostics': subscription_diagnostics,
                  'exclusions': exclusions,
                  'prepare_script_sha256': digest(read(Path(__file__))),
                  'files': {name: {'sha256': digest(data), 'size_bytes': len(data)} for name, data in inputs.items()},
                  'limits': 'Parser/resource loading only; renderer/network behavior remains separate acceptance.'}
    output.mkdir(mode=0o700)
    for name, data in inputs.items():
        with (output / name).open('xb') as stream:
            stream.write(data)
    with (output / 'assets.json').open('x') as stream:
        json.dump(provenance, stream, indent=2)
        stream.write('\n')
    print(json.dumps({'status': 'prepared', 'output': str(output), 'tracker_domains': own_provenance['domain_count']}))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print('Asset preparation failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
