function downloadRange(header, size) {
  if (!header) return { start: 0, end: size - 1, partial: false };
  const match = /^bytes=(\d*)-(\d*)$/.exec(header);
  if (!match || (!match[1] && !match[2])) return null;
  const start = match[1] ? Number(match[1]) : Math.max(0, size - Number(match[2]));
  const end = match[1] && match[2] ? Math.min(Number(match[2]), size - 1) : size - 1;
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start >= size || end < start) return null;
  return { start, end, partial: true };
}

function downloadStream(assets, origin, apk, range) {
  let part = Math.floor(range.start / apk.chunkSize);
  let offset = part * apk.chunkSize;
  let remaining = range.end - range.start + 1;
  let reader;
  let cancelled = false;
  return new ReadableStream({
    async pull(controller) {
      try {
        while (remaining > 0 && !cancelled) {
          if (!reader) {
            const url = new URL(`/downloads/part-${String(part).padStart(3, '0')}.bin.gz`, origin);
            const response = await assets.fetch(new Request(url));
            if (cancelled) { await response.body?.cancel(); return; }
            if (response.status !== 200 || !response.body) throw new Error('Download part unavailable');
            reader = response.body.pipeThrough(new DecompressionStream('gzip')).getReader();
          }
          const { done, value } = await reader.read();
          if (cancelled) return;
          if (done) {
            reader.releaseLock();
            reader = undefined;
            if (offset !== Math.min((part + 1) * apk.chunkSize, apk.size)) throw new Error('Download part has incorrect length');
            part += 1;
            continue;
          }
          const skip = Math.max(0, range.start - offset);
          const take = Math.min(Math.max(0, value.length - skip), remaining);
          offset += value.length;
          if (take > 0) {
            controller.enqueue(value.subarray(skip, skip + take));
            remaining -= take;
            if (remaining === 0) {
              await reader.cancel();
              reader.releaseLock();
              reader = undefined;
              controller.close();
            }
            return;
          }
        }
      } catch (error) {
        if (reader) { await reader.cancel().catch(() => {}); reader.releaseLock(); reader = undefined; }
        if (!cancelled) controller.error(error);
      }
    },
    async cancel(reason) {
      cancelled = true;
      if (reader) await reader.cancel(reason);
    },
  });
}

export async function fetchDownload(request, env, apk) {
  const url = new URL(request.url);
  if (url.pathname !== `/${apk.filename}`) return env.ASSETS.fetch(request);
  if (request.method !== 'GET' && request.method !== 'HEAD') return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
  const etag = `"${apk.sha256}"`;
  if (request.headers.get('if-none-match') === etag) return new Response(null, { status: 304, headers: { ETag: etag } });
  const ifRange = request.headers.get('if-range');
  const range = downloadRange(ifRange && ifRange !== etag ? null : request.headers.get('range'), apk.size);
  if (!range) return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${apk.size}`, 'Accept-Ranges': 'bytes' } });
  const headers = {
    'Content-Type': 'application/vnd.android.package-archive',
    'Content-Disposition': `attachment; filename="${apk.filename}"`,
    'Content-Length': String(range.end - range.start + 1),
    'Accept-Ranges': 'bytes',
    'Cache-Control': 'public, max-age=3600, no-transform',
    'X-Content-Type-Options': 'nosniff',
    ETag: etag,
  };
  if (range.partial) headers['Content-Range'] = `bytes ${range.start}-${range.end}/${apk.size}`;
  const body = request.method === 'HEAD' ? null : downloadStream(env.ASSETS, url.origin, apk, range);
  return new Response(body, { status: range.partial ? 206 : 200, headers });
}
