import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync, renameSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';

// Run after recording lessons or modifying their MP4s. Pin the actual encoding,
// not just metadata: variable input timestamps can make x264 choose Level 6.2.
const ffmpeg = process.env.FFMPEG_BINARY ?? 'ffmpeg';
const directory = resolve(process.argv[2] ?? 'public/tutorial');
const ids = [
  'stacking',
  'horizontal',
  'vertical',
  'diagonal-flat',
  'diagonal-third-layer',
  'diagonal-space',
];
function run(args) {
  return execFileSync(ffmpeg, ['-hide_banner', ...args], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}
for (const id of ids) {
  const source = join(directory, `${id}.mp4`);
  const temporary = join(directory, `${id}.compatible.mp4`);
  try {
    const scan = spawnSync(
      ffmpeg,
      ['-hide_banner', '-i', source, '-vf', 'blackdetect=d=0:pix_th=0.1', '-an', '-f', 'null', '-'],
      { encoding: 'utf8' },
    );
    if (scan.status !== 0) throw new Error(scan.error?.message ?? scan.stderr);
    const start = scan.stderr.match(/black_start:0(?:\.0*)? black_end:([\d.]+)/)?.[1] ?? '0';
    run([
      '-loglevel',
      'error',
      '-y',
      '-i',
      source,
      '-vf',
      `trim=start=${start},setpts=PTS-STARTPTS,fps=30,scale=in_range=auto:out_range=tv`,
      '-an',
      '-c:v',
      'libx264',
      '-preset',
      'slow',
      '-crf',
      '18',
      '-profile:v',
      'baseline',
      '-level:v',
      '3.1',
      '-bf',
      '0',
      '-refs',
      '2',
      '-g',
      '30',
      '-keyint_min',
      '30',
      '-pix_fmt',
      'yuv420p',
      '-color_range',
      'tv',
      '-colorspace',
      'bt709',
      '-color_primaries',
      'bt709',
      '-color_trc',
      'bt709',
      '-maxrate',
      '3000k',
      '-bufsize',
      '6000k',
      '-movflags',
      '+faststart',
      temporary,
    ]);
    const bytes = readFileSync(temporary);
    const avc = bytes.indexOf('avcC');
    if (avc < 0 || bytes[avc + 5] !== 66 || bytes[avc + 7] !== 31)
      throw new Error(`${id}: unexpected H.264 profile/level`);
    run([
      '-loglevel',
      'error',
      '-y',
      '-i',
      temporary,
      '-frames:v',
      '1',
      '-c:v',
      'libwebp',
      '-quality',
      '90',
      join(directory, `${id}-start.webp`),
    ]);
    renameSync(temporary, source);
    console.log(`${id}: H.264 Baseline 3.1 / 30 fps, fast start and opening cover`);
  } finally {
    rmSync(temporary, { force: true });
  }
}
