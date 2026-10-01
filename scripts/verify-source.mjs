import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const archive = process.argv[2];
if (!archive) throw new Error('Usage: node scripts/verify-source.mjs <archive.tar.gz>');
const manifest = execFileSync('tar', ['-xOf', archive, 'four-in-a-row/SOURCE-MANIFEST.sha256'],
  { maxBuffer: 16 * 1024 * 1024 }).toString('utf8').trimEnd().split('\n');
for (const line of manifest) {
  const match = /^([a-f0-9]{64}) {2}(.+)$/.exec(line);
  if (!match) throw new Error(`Malformed entry: ${line}`);
  const content = execFileSync('tar', ['-xOf', archive, `four-in-a-row/${match[2]}`],
    { maxBuffer: 32 * 1024 * 1024 });
  const actual = createHash('sha256').update(content).digest('hex');
  if (actual !== match[1]) throw new Error(`Hash mismatch: ${match[2]}`);
}
const archiveDigest = createHash('sha256').update(readFileSync(archive)).digest('hex');
console.log(`Verified ${manifest.length} source files; archive SHA-256 ${archiveDigest}`);
