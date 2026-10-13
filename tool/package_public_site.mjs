import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { cp, mkdir, open, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const site = path.join(root, '.local/public-site');
const distribution = path.join(root, 'dist/android');
const filename = 'zad-alruh-0.3.0+3-debug.apk';
const apkPath = path.join(distribution, filename);
const chunkSize = 20 * 1024 * 1024;
const size = (await stat(apkPath)).size;
const hash = createHash('sha256');
for await (const bytes of createReadStream(apkPath)) hash.update(bytes);
const sha256 = hash.digest('hex').toUpperCase();
if (sha256 !== '0816E22F80ADA6732CC3638D99753289B14CB50663D75DEC86181EB4EA6B8A1B') throw new Error('Approved APK hash changed');
await mkdir(path.join(site, 'src'), { recursive: true });
await mkdir(path.join(site, 'public/downloads'), { recursive: true });
await cp(path.join(distribution, 'assets'), path.join(site, 'public/assets'), { recursive: true });
await cp(path.join(distribution, 'index.html'), path.join(site, 'public/index.html'));
const file = await open(apkPath, 'r');
try {
  for (let offset = 0, part = 0; offset < size; offset += chunkSize, part += 1) {
    const buffer = Buffer.alloc(Math.min(chunkSize, size - offset));
    let filled = 0;
    while (filled < buffer.length) {
      const { bytesRead } = await file.read(buffer, filled, buffer.length - filled, offset + filled);
      if (bytesRead === 0) throw new Error('APK changed while packaging');
      filled += bytesRead;
    }
    await writeFile(path.join(site, `public/downloads/part-${String(part).padStart(3, '0')}.bin.gz`), gzipSync(buffer, { level: 9 }));
  }
} finally { await file.close(); }
const metadata = { filename, size, chunkSize, sha256 };
await writeFile(path.join(site, 'src/apk-meta.js'), `export default ${JSON.stringify(metadata)};\n`);
await cp(path.join(root, 'tool/public_download_worker.mjs'), path.join(site, 'src/worker.mjs'));
await cp(path.join(root, 'tool/public_site_build.mjs'), path.join(site, 'build.mjs'));
await writeFile(path.join(site, 'package.json'), JSON.stringify({ name: 'zad-alruh-public-download', private: true, type: 'module', scripts: { build: 'node build.mjs' } }, null, 2) + '\n');
await writeFile(path.join(site, '.gitignore'), 'dist/\nnode_modules/\n');
await writeFile(path.join(site, '.gitattributes'), '*.gz binary\n*.png binary\n');
await writeFile(path.join(site, 'README.md'), 'Approved landing page with streamed Android APK download. No app source or credentials are included.\n');
console.log(JSON.stringify({ site, ...metadata, parts: Math.ceil(size / chunkSize) }));
