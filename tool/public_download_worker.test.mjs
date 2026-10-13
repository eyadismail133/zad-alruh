import assert from 'node:assert/strict';
import { test } from 'node:test';
import { gzipSync } from 'node:zlib';
import { fetchDownload } from './public_download_worker.mjs';

const bytes = Uint8Array.from({ length: 47 }, (_, i) => i);
const apk = { filename: 'app.apk', size: bytes.length, chunkSize: 7, sha256: 'test-digest' };

function environment(missing = -1) {
  return {
    ASSETS: {
      async fetch(request) {
        const pathname = new URL(typeof request === 'string' ? request : request.url).pathname;
        const match = pathname.match(/^\/downloads\/part-(\d+)\.bin\.gz$/);
        if (!match) return new Response('landing page');
        const index = Number(match[1]);
        if (index === missing) return new Response('missing', { status: 404 });
        return new Response(gzipSync(bytes.slice(index * apk.chunkSize, (index + 1) * apk.chunkSize)));
      },
    },
  };
}

test('download streams the complete original binary with APK attachment headers', async () => {
  const response = await fetchDownload(new Request('https://example.test/app.apk'), environment(), apk);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-length'), String(bytes.length));
  assert.equal(response.headers.get('content-type'), 'application/vnd.android.package-archive');
  assert.match(response.headers.get('content-disposition'), /attachment; filename="app.apk"/);
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), bytes);
});

test('resumed, open-ended and suffix downloads preserve exact bytes across chunk boundaries', async () => {
  for (const [range, start, end] of [['bytes=5-17', 5, 17], ['bytes=40-', 40, 46], ['bytes=-9', 38, 46], ['bytes=0-999', 0, 46]]) {
    const response = await fetchDownload(new Request('https://example.test/app.apk', { headers: { range } }), environment(), apk);
    assert.equal(response.status, 206, range);
    assert.equal(response.headers.get('content-range'), `bytes ${start}-${end}/${bytes.length}`);
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()), bytes.slice(start, end + 1));
  }
});

test('invalid ranges and unsupported methods do not return a corrupt APK', async () => {
  for (const range of ['bytes=100-', 'bytes=20-10', 'bytes=-0', 'bytes=0-1,3-5', 'bytes=']) {
    const response = await fetchDownload(new Request('https://example.test/app.apk', { headers: { range } }), environment(), apk);
    assert.equal(response.status, 416, range);
    assert.equal(response.headers.get('content-range'), `bytes */${bytes.length}`);
  }
  const response = await fetchDownload(new Request('https://example.test/app.apk', { method: 'POST' }), environment(), apk);
  assert.equal(response.status, 405);
});

test('HEAD returns download metadata without a body; stale If-Range restarts the full file', async () => {
  const head = await fetchDownload(new Request('https://example.test/app.apk', { method: 'HEAD' }), environment(), apk);
  assert.equal(head.headers.get('content-length'), String(bytes.length));
  assert.equal(await head.text(), '');
  const restarted = await fetchDownload(new Request('https://example.test/app.apk', { headers: { range: 'bytes=40-', 'if-range': '"old-digest"' } }), environment(), apk);
  assert.equal(restarted.status, 200);
  assert.deepEqual(new Uint8Array(await restarted.arrayBuffer()), bytes);
});

test('missing chunk aborts the download instead of returning successful truncated data', async () => {
  const response = await fetchDownload(new Request('https://example.test/app.apk'), environment(2), apk);
  await assert.rejects(response.arrayBuffer(), /Download part unavailable/);
});

test('normal page requests still reach the original site assets', async () => {
  const response = await fetchDownload(new Request('https://example.test/'), environment(), apk);
  assert.equal(await response.text(), 'landing page');
});
