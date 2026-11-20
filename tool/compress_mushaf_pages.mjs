// Shrinks the 604 bundled Mushaf page images without changing their geometry.
//
// The pages are rendered from vector SVGs as near-black anti-aliased ink on a
// white background. Almost all of their lossless WebP size is spent on the
// ~250 grey levels of anti-aliasing. This tool:
//   1. converts each page to a single grey channel (pages carry no colour:
//      max channel spread is 4/255),
//   2. snaps every pixel to 4 evenly spaced levels between the page's ink
//      level and paper white (ink, 2 edge greys, white),
//   3. re-encodes as lossless WebP (method 6).
// Resolution (1200x1913), glyph shapes and page layout stay exactly the same;
// only the softness of the anti-aliased edge changes (mean abs. error < 1/255).
// Lossy WebP was measured to be *larger* than this for sharp text.
//
// It then rewrites the pinned digests everywhere they are recorded, so
// ContentValidator stays green in the same commit (see AGENTS.md section 5).
//
// Usage (from the repo root; sharp is a dev-only dependency, not committed):
//   npm i --no-save --prefix .local/sharp sharp@0.34.3
//   NODE_PATH=.local/sharp/node_modules node tool/compress_mushaf_pages.mjs
//
// Running it twice is a no-op: already-quantised pages map to themselves.

import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const sharp = require('sharp');
sharp.cache(false); // Windows: do not keep page files open while rewriting them.

const LEVELS = 4;
const ROOT = process.cwd();
const PAGES_DIR = path.join(ROOT, 'assets/content/quran/pages');
const DIGESTS = path.join(ROOT, 'assets/content/quran/quran-pages-digests.json');
const PINNED_FILES = [
  'assets/content/manifest.json',
  'lib/src/core/content/content_validator.dart',
  'lib/src/features/quran/data/sources/kfqc_mushaf_catalog.dart',
  'docs/sources/KFQC_MUSHAF.md',
  'docs/HUMAN-CONTENT-REVIEW.md',
];
const RENDER_NOTE =
  `; greyscale ${LEVELS}-level quantisation + libwebp lossless method 6 (tool/compress_mushaf_pages.mjs)`;

const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');

async function quantisePage(input) {
  const { data, info } = await sharp(input)
    .toColourspace('b-w')
    .raw()
    .toBuffer({ resolveWithObject: true });
  let ink = 255;
  for (const v of data) if (v < ink) ink = v;
  const step = (255 - ink) / (LEVELS - 1);
  if (step > 0) {
    for (let i = 0; i < data.length; i++) {
      data[i] = Math.round(ink + Math.round((data[i] - ink) / step) * step);
    }
  }
  return sharp(data, { raw: { width: info.width, height: info.height, channels: 1 } })
    .webp({ lossless: true, effort: 6 })
    .toBuffer();
}

const digestsText = fs.readFileSync(DIGESTS, 'utf8');
const oldDigestsSha = sha256(fs.readFileSync(DIGESTS));
let newDigestsText = digestsText;
const replacements = new Map();
let oldTotal = 0;
let newTotal = 0;

for (let page = 1; page <= 604; page++) {
  const name = `${String(page).padStart(3, '0')}.webp`;
  const file = path.join(PAGES_DIR, name);
  const before = fs.readFileSync(file);
  const after = await quantisePage(before);
  const oldSha = sha256(before);
  const newSha = sha256(after);
  oldTotal += before.length;
  newTotal += after.length;
  fs.writeFileSync(file, after);

  // Rewrite this page's entry in place, keeping the file's CRLF formatting.
  const entry = new RegExp(
    `("page": ${page},[\\s\\S]*?"webp_sha256": ")${oldSha}(",\\s*"webp_size": )${before.length}`,
  );
  if (!entry.test(newDigestsText)) {
    throw new Error(`Digest entry for page ${page} does not match ${oldSha}`);
  }
  newDigestsText = newDigestsText.replace(entry, `$1${newSha}$2${after.length}`);
  if (page === 1 || page === 604) replacements.set(oldSha, newSha);
  if (page % 100 === 0) console.log(`page ${page}: ${before.length} -> ${after.length}`);
}

if (!newDigestsText.includes(RENDER_NOTE)) {
  newDigestsText = newDigestsText.replace(/("render": "[^"]*)"/, `$1${RENDER_NOTE}"`);
}
fs.writeFileSync(DIGESTS, newDigestsText);
const newDigestsSha = sha256(fs.readFileSync(DIGESTS));
replacements.set(oldDigestsSha, newDigestsSha);

for (const rel of PINNED_FILES) {
  const file = path.join(ROOT, rel);
  let text = fs.readFileSync(file, 'utf8');
  for (const [from, to] of replacements) text = text.split(from).join(to);
  text = text.split(String(oldTotal)).join(String(newTotal));
  if (rel.endsWith('manifest.json') && !text.includes('quantisation')) {
    text = text.replace(
      /("image_encoder": "[^"]*)"/,
      `$1; then greyscale ${LEVELS}-level quantisation, libwebp lossless (tool/compress_mushaf_pages.mjs)"`,
    );
  }
  fs.writeFileSync(file, text);
}

console.log(`total ${oldTotal} -> ${newTotal} bytes (${((100 * newTotal) / oldTotal).toFixed(1)}%)`);
console.log(`digests sha ${oldDigestsSha} -> ${newDigestsSha}`);
