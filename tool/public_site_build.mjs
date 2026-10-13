import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { cp, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createGunzip } from 'node:zlib';
import apk from './src/apk-meta.js';

const site = path.dirname(fileURLToPath(import.meta.url));
const hash = createHash('sha256');
let size = 0;
for (let part = 0; part < Math.ceil(apk.size / apk.chunkSize); part += 1) {
  const filename = path.join(site, `public/downloads/part-${String(part).padStart(3, '0')}.bin.gz`);
  for await (const bytes of createReadStream(filename).pipe(createGunzip())) { hash.update(bytes); size += bytes.length; }
}
if (size !== apk.size || hash.digest('hex').toUpperCase() !== apk.sha256) throw new Error('APK source integrity verification failed');
await mkdir(path.join(site, 'dist/server'), { recursive: true });
await cp(path.join(site, 'public'), path.join(site, 'dist/client'), { recursive: true });
await cp(path.join(site, 'src/worker.mjs'), path.join(site, 'dist/server/worker.js'));
await cp(path.join(site, 'src/apk-meta.js'), path.join(site, 'dist/server/apk-meta.js'));
await writeFile(path.join(site, 'dist/server/index.js'), "import apk from './apk-meta.js';\nimport { fetchDownload } from './worker.js';\nexport default { fetch(request, env) { return fetchDownload(request, env, apk); } };\n");
console.log(`Built public download site; verified ${size} APK bytes (${apk.sha256}).`);
