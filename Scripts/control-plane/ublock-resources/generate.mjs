// generate.mjs <uBlock source folder> <output.json>
//
// Builds the resources Crest's content filter loads for scriptlets (`##+js(...)`)
// and `$redirect` filters from a uBlock Origin source release, in adblock-rust's
// resource format: each scriptlet and each function it depends on, as source, and
// each redirect resource, as data. uBlock Origin's resources are GPL-3.0; Crest
// fetches the generated file at runtime as data and never compiles it in.
// Scriptlets uBlock runs only for trusted lists carry the permission only
// Crest's own lists hold; those it runs only in an isolated world are left out.
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join, extname } from 'node:path';
import { pathToFileURL } from 'node:url';

const [source, output] = process.argv.slice(2);
if (!source || !output) {
  console.error('usage: generate.mjs <uBlock source folder> <output.json>');
  process.exit(64);
}
const base64 = (text) => Buffer.from(text).toString('base64');
const { builtinScriptlets } = await import(pathToFileURL(join(source, 'src/js/resources/scriptlets.js')).href);
const resources = [];
const names = new Set();
const skipped = [];
// A scriptlet uBlock runs only for trusted lists needs adblock-rust's
// permission bit 1, which only the lists Crest itself chooses carry.
const trusted = 1;
for (const scriptlet of builtinScriptlets) {
  if (scriptlet.world === 'ISOLATED') { skipped.push(scriptlet.name); continue; }
  if (names.has(scriptlet.name)) continue;
  names.add(scriptlet.name);
  resources.push({
    name: scriptlet.name,
    aliases: scriptlet.aliases ?? [],
    kind: { mime: scriptlet.name.endsWith('.fn') ? 'fn/javascript' : 'application/javascript' },
    content: base64(scriptlet.fn.toString()),
    dependencies: scriptlet.dependencies ?? [],
    ...(scriptlet.requiresTrust ? { permission: trusted } : {}),
  });
}
// A dependency left out with its scriptlet would break those that need it.
const missing = resources.flatMap((resource) => resource.dependencies).filter((name) => !names.has(name));
for (const name of new Set(missing)) {
  const scriptlet = builtinScriptlets.find((entry) => entry.name === name);
  if (!scriptlet) continue;
  names.add(name);
  resources.push({ name, aliases: scriptlet.aliases ?? [], kind: { mime: 'fn/javascript' },
    content: base64(scriptlet.fn.toString()), dependencies: scriptlet.dependencies ?? [] });
}
// Redirect resources: uBlock's map names each file in web_accessible_resources
// and its aliases.
const mimes = { '.js': 'application/javascript', '.gif': 'image/gif', '.png': 'image/png', '.html': 'text/html',
  '.txt': 'text/plain', '.json': 'application/json', '.mp3': 'audio/mp3', '.mp4': 'video/mp4', '.css': 'text/css', '.xml': 'text/xml' };
const { default: redirects } = await import(pathToFileURL(join(source, 'src/js/redirect-resources.js')).href);
const files = new Set(readdirSync(join(source, 'src/web_accessible_resources')));
for (const [name, details] of redirects) {
  const file = name;
  if (!files.has(file) || names.has(name)) continue;
  const mime = mimes[extname(file)];
  if (!mime) continue;
  const bytes = readFileSync(join(source, 'src/web_accessible_resources', file));
  names.add(name);
  resources.push({ name, aliases: details?.alias ? [].concat(details.alias) : [], kind: { mime },
    content: bytes.toString('base64'), dependencies: [] });
}
resources.sort((a, b) => a.name.localeCompare(b.name));
writeFileSync(output, JSON.stringify(resources) + '\n');
console.log(JSON.stringify({ resources: resources.length,
  scriptlets: resources.filter((r) => r.kind.mime === 'application/javascript' && r.name.endsWith('.js') && !files.has(r.name)).length,
  functions: resources.filter((r) => r.kind.mime === 'fn/javascript').length,
  redirects: resources.filter((r) => files.has(r.name)).length, trusted: resources.filter((r) => r.permission).length,
  skipped: skipped.length }));
