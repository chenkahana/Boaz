#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const storage = '/Volumes/BoazBuild/cef/direct/adblock';
const here = path.dirname(fileURLToPath(import.meta.url));
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const fail = message => { throw new Error(message); };

async function canonical(file, allowMissingLeaf = false) {
  const absolute = path.resolve(file);
  if (!absolute.startsWith(`${storage}/`)) fail('Path outside approved adblock storage');
  const parts = absolute.split(path.sep).filter(Boolean);
  let current = path.sep;
  for (let i = 0; i < parts.length; i++) {
    current = path.join(current, parts[i]);
    try {
      const stat = await fs.lstat(current);
      if (stat.isSymbolicLink()) fail(`Symlink refused: ${current}`);
      if (i < parts.length - 1 && !stat.isDirectory()) fail('Non-directory parent');
    } catch (error) {
      if (error.code === 'ENOENT' && allowMissingLeaf && i === parts.length - 1) return absolute;
      throw error;
    }
  }
  return absolute;
}

async function main() {
  if (process.argv.length !== 3) fail('Usage: node --experimental-vm-modules package-resources.mjs /Volumes/BoazBuild/cef/direct/adblock/<new-output>.json');
  if (!vm.SourceTextModule) fail('Node requires --experimental-vm-modules');
  const output = await canonical(process.argv[2], true);
  if (!output.endsWith('.json')) fail('Output must end in .json');
  for (const name of [output, `${output}.receipt.json`]) {
    try { await fs.lstat(name); fail(`Refusing existing output: ${name}`); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  const lockBytes = await fs.readFile(path.join(here, 'resources.lock.json'));
  const listsBytes = await fs.readFile(path.join(here, 'lists.lock.json'));
  const lock = JSON.parse(lockBytes);
  const lists = JSON.parse(listsBytes);
  if (lock.schema_version !== 1 || lists.schema_version !== 1) fail('Unsupported lock schema');
  const files = new Map();
  for (const item of lock.files) {
    const filename = await canonical(item.artifact_path);
    if (!(await fs.stat(filename)).isFile()) fail('Input must be a regular file');
    const bytes = await fs.readFile(filename);
    if (bytes.length !== item.size_bytes || sha(bytes) !== item.sha256) fail(`Input hash/size mismatch: ${item.path}`);
    const key = `${item.repository}:${item.path}`;
    if (files.has(key)) fail(`Duplicate input: ${key}`);
    files.set(key, { ...item, bytes });
  }
  const ubo = 'brave/uBlock';
  const get = (repo, file) => files.get(`${repo}:${file}`) ?? fail(`Unpinned input: ${repo}:${file}`);
  const context = vm.createContext(Object.create(null), { codeGeneration: { strings: false, wasm: false } });
  const modules = new Map();
  function load(file) {
    if (modules.has(file)) return modules.get(file);
    const source = get(ubo, file).bytes.toString('utf8');
    const module = new vm.SourceTextModule(source, { context, identifier: file,
      importModuleDynamically: () => fail('Dynamic import refused') });
    modules.set(file, module);
    return module;
  }
  const linker = (specifier, parent) => {
    if (!specifier.startsWith('./') && !specifier.startsWith('../')) fail('Non-relative module import');
    const file = path.posix.normalize(path.posix.join(path.posix.dirname(parent.identifier), specifier));
    if (!file.startsWith('src/js/')) fail('Module outside pinned resource closure');
    return load(file);
  };
  const scriptlets = load('src/js/resources/scriptlets.js');
  await scriptlets.link(linker);
  await scriptlets.evaluate({ timeout: 5000 });
  const builtins = scriptlets.namespace.builtinScriptlets;
  if (!Array.isArray(builtins)) fail('Missing upstream builtinScriptlets');
  const byName = new Map();
  const aliases = new Map();
  for (const item of builtins) {
    if (typeof item.name !== 'string' || typeof item.fn !== 'function') fail('Invalid scriptlet entry');
    if (byName.has(item.name)) fail(`Duplicate scriptlet: ${item.name}`);
    byName.set(item.name, item);
    for (const name of [item.name, ...(item.aliases ?? [])]) {
      if (aliases.has(name)) fail(`Duplicate scriptlet alias: ${name}`);
      aliases.set(name, item.name);
    }
  }
  const requiredScripts = new Set(lists.lists.flatMap(list => list.scriptlet_names));
  const selected = new Set();
  function select(name) {
    const canonicalName = aliases.get(name) ?? fail(`Unresolved scriptlet: ${name}`);
    if (selected.has(canonicalName)) return;
    selected.add(canonicalName);
    const item = byName.get(canonicalName);
    for (const dependency of item.dependencies ?? []) {
      if (typeof dependency !== 'string' || !byName.has(dependency)) fail(`Unresolved dependency: ${canonicalName}`);
      select(dependency);
    }
  }
  for (const name of requiredScripts) select(`${name}.js`);
  const expected = Object.keys(lock.scriptlet_dependency_closure).sort();
  if (JSON.stringify([...selected].sort()) !== JSON.stringify(expected)) fail('Scriptlet closure differs from reviewed lock');
  const resources = [];
  const worlds = {};
  for (const name of [...selected].sort()) {
    const item = byName.get(name);
    if (item.requiresTrust !== undefined && typeof item.requiresTrust !== 'boolean') fail('Unknown trust metadata');
    if (item.world !== undefined && !['MAIN', 'ISOLATED'].includes(item.world)) fail('Unknown scriptlet world');
    resources.push({ name, aliases: [...(item.aliases ?? [])], kind: { mime: 'application/javascript' },
      content: Buffer.from(Function.prototype.toString.call(item.fn)).toString('base64'),
      dependencies: [...(item.dependencies ?? [])], permission: item.requiresTrust ? 1 : 0 });
    worlds[name] = { declared_world: item.world ?? null, execution_world: item.world ?? 'MAIN', requires_trust: item.requiresTrust ?? false };
  }
  const redirects = load('src/js/redirect-resources.js');
  await redirects.link(() => fail('Unexpected redirect module import'));
  await redirects.evaluate({ timeout: 5000 });
  const redirectMap = redirects.namespace.default;
  const redirectNames = new Map();
  for (const [name, detail] of redirectMap) {
    const names = [name, ...(Array.isArray(detail.alias) ? detail.alias : detail.alias ? [detail.alias] : [])];
    for (const alias of names) {
      if (redirectNames.has(alias)) fail(`Duplicate redirect alias: ${alias}`);
      redirectNames.set(alias, { name, detail, aliases: names.slice(1) });
    }
  }
  const requiredRedirects = new Set(lists.lists.flatMap(list => list.resource_names));
  const chosenRedirects = new Map();
  for (const alias of requiredRedirects) {
    const entry = redirectNames.get(alias) ?? fail(`Unresolved redirect: ${alias}`);
    if (lock.redirect_resource_mapping[alias] !== entry.name) fail('Redirect mapping differs from reviewed lock');
    chosenRedirects.set(entry.name, entry);
  }
  const mime = { '.gif': 'image/gif', '.js': 'application/javascript', '.json': 'application/json', '.txt': 'text/plain', '.mp4': 'video/mp4' };
  for (const [name, entry] of [...chosenRedirects].sort(([a], [b]) => a.localeCompare(b))) {
    if (entry.detail.params !== undefined) fail(`Unsupported redirect params: ${name}`);
    const type = mime[path.extname(name)] ?? fail(`Unsupported MIME: ${name}`);
    const bytes = get(ubo, `src/web_accessible_resources/${name}`).bytes;
    resources.push({ name, aliases: entry.aliases, kind: { mime: type }, content: bytes.toString('base64'), dependencies: [], permission: 0 });
  }
  const identifiers = new Set();
  for (const resource of resources) {
    for (const name of [resource.name, ...resource.aliases]) {
      if (identifiers.has(name)) fail(`Duplicate packaged identifier: ${name}`);
      identifiers.add(name);
    }
  }
  const bytes = Buffer.from(`${JSON.stringify(resources)}\n`);
  if (bytes.length > 64 * 1024 * 1024) fail('Resource package too large');
  const receipt = { schema_version: 1, resources_lock_sha256: sha(lockBytes), lists_lock_sha256: sha(listsBytes),
    package_script_sha256: sha(await fs.readFile(fileURLToPath(import.meta.url))),
    sha256: sha(bytes), size_bytes: bytes.length, resource_count: resources.length,
    scriptlet_count: selected.size, redirect_count: chosenRedirects.size, public_list_permission_mask: 0,
    input_files_verified: files.size, worlds, licenses: lock.licenses,
    custom_resources: 'Pinned Brave custom resource JSON verified, but none required by this selected list dependency closure.',
    assembly_reference: lock.assembly, runtime_validation: 'Pending pinned Rust resource loading and renderer execution' };
  const dataFile = await fs.open(output, 'wx', 0o600);
  try { await dataFile.writeFile(bytes); await dataFile.sync(); } finally { await dataFile.close(); }
  const receiptFile = await fs.open(`${output}.receipt.json`, 'wx', 0o600);
  try { await receiptFile.writeFile(`${JSON.stringify(receipt, null, 2)}\n`); await receiptFile.sync(); } finally { await receiptFile.close(); }
  console.log(JSON.stringify({ output, sha256: receipt.sha256, size_bytes: bytes.length, resource_count: resources.length, scriptlet_count: selected.size, redirect_count: chosenRedirects.size }));
}
main().catch(error => { console.error(`Resource packaging failed: ${error.message}`); process.exitCode = 1; });
