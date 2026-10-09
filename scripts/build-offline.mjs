import { createHash } from 'node:crypto';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');
const worker = await readFile('public/match-notifications.js', 'utf8');
const entries = [];
async function collect(directory = '') {
  for (const entry of await readdir(join('dist', directory), { withFileTypes: true })) {
    const path = directory ? `${directory}/${entry.name}` : entry.name;
    if (entry.isDirectory()) await collect(path);
    else if (
      path !== 'match-notifications.js' &&
      !path.startsWith('.well-known/') &&
      path !== 'indexnow-key.txt'
    ) {
      const bytes = await readFile(join('dist', path));
      entries.push({
        url: path === 'index.html' ? '/' : `/${path}`,
        hash: digest(bytes),
        size: bytes.length,
      });
    }
  }
}
await collect();
entries.sort((a, b) => a.url.localeCompare(b.url));
const version = digest(worker + JSON.stringify(entries)).slice(0, 20);
await writeFile(
  'dist/match-notifications.js',
  worker.replace(
    'const OFFLINE_BUILD = null;',
    `const OFFLINE_BUILD = ${JSON.stringify({ version, entries })};`,
  ),
);
console.log(
  `Offline build ${version}: ${entries.length} files, ${(entries.reduce((sum, entry) => sum + entry.size, 0) / 1024 / 1024).toFixed(1)} MB`,
);
