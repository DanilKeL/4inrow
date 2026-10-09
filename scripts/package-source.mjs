import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, copyFileSync, writeFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = resolve(process.argv[2] ?? join(root, 'artifacts/source'));
const project = 'four-in-a-row';
const roots = ['assets', 'deploy', 'e2e', 'public', 'references', 'scripts', 'server', 'src'];
const files = ['.gitignore', '.prettierrc.json', 'eslint.config.js',
  'index.html', 'package-lock.json', 'package.json', 'playwright.config.ts', 'playwright.offline.config.ts', 'README.md',
  'THIRD_PARTY_NOTICES.md', 'tsconfig.json', 'vite.config.ts'];
const blockedDirectories = new Set(['build', 'node_modules', '.idea', '.cache']);
const entries = [];
let totalBytes = 0;
const timestamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
const archiveName = `four-game-source-${timestamp}.tar.gz`;

function include(path) {
  const relativePath = relative(root, path).split(sep).join('/');
  if (relativePath.endsWith('.blend1') || relativePath.endsWith('.log')) return false;
  return true;
}
function walk(path) {
  for (const child of readdirSync(path, { withFileTypes: true })) {
    if (blockedDirectories.has(child.name) && child.isDirectory()) continue;
    const target = join(path, child.name);
    if (child.isDirectory()) walk(target);
    else if (child.isFile() && include(target)) entries.push(target);
    else if (child.isSymbolicLink()) throw new Error(`Unexpected symbolic link: ${target}`);
  }
}
for (const directory of roots) walk(join(root, directory));
for (const file of files) {
  const path = join(root, file);
  if (!existsSync(path)) throw new Error(`Missing source file: ${file}`);
  entries.push(path);
}
entries.sort((a, b) => a.localeCompare(b));

mkdirSync(output, { recursive: true });
const stage = mkdtempSync(join(tmpdir(), 'four-game-source-'));
try {
  const dest = join(stage, project);
  for (const source of entries) {
    const rel = relative(root, source);
    const target = join(dest, rel);
    mkdirSync(dirname(target), { recursive: true });
    copyFileSync(source, target);
    const bytes = readFileSync(source);
    totalBytes += bytes.length;
  }
  const manifest = entries.map((source) => {
    const rel = relative(root, source).split(sep).join('/');
    const digest = createHash('sha256').update(readFileSync(source)).digest('hex');
    return `${digest}  ${rel}`;
  });
  writeFileSync(join(dest, 'SOURCE-MANIFEST.sha256'), manifest.join('\n') + '\n');
  writeFileSync(join(dest, 'START-HERE.txt'),
    'FOUR³ source archive\n\n' +
    'Web: install Node.js 22+, run npm ci, then npm run dev.\n' +
    'Server: npm run build, then npm start.\n' +
    'Build outputs and dependencies are not part of this source archive.\n');
  const archive = join(output, archiveName);
  execFileSync('tar', ['-czf', archive, '-C', stage, project], { stdio: 'inherit' });
  const sha256 = createHash('sha256').update(readFileSync(archive)).digest('hex');
  writeFileSync(`${archive}.sha256`, `${sha256}  ${archiveName}\n`);
  const report = { archive, sha256, files: entries.length + 2, sourceBytes: totalBytes, archiveBytes: statSync(archive).size };
  writeFileSync(join(output, 'latest-source.json'), JSON.stringify(report, null, 2) + '\n');
  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
} finally {
  rmSync(stage, { recursive: true, force: true });
}
