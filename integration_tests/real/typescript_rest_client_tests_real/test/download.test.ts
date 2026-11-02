import { beforeEach, describe, expect, it } from 'vitest';
import { RestError, type GraphLinkClient } from '../lib/generated/graphlink';
import { variant } from './variant';
import { newClient, pattern, resetServer, sha256Of, uploadOf } from './support';

let client: GraphLinkClient;

beforeEach(async () => {
  await resetServer();
  client = newClient();
});

describe('download', () => {
  it('metadata comes from the response headers and bytes are exact', async () => {
    const d = await client.queries.blob({ size: 100000 });
    expect(d.filename).toBe('blob-100000.bin');
    expect(d.contentType).toMatch(/^application\/octet-stream/);
    expect(d.length).toBe(100000);
    expect(await d.bytes()).toEqual(pattern(100000));
  });

  it('the body is streamed and a multi-megabyte download arrives intact', async () => {
    const size = 8 * 1024 * 1024;
    const d = await client.queries.blob({ size });
    const reader = d.stream.getReader();
    const all: Uint8Array[] = [];
    let received = 0;
    let chunks = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      received += value.length;
      chunks++;
      all.push(value);
    }
    expect(received).toBe(size);
    if (variant.adapter !== 'axios') expect(chunks).toBeGreaterThan(1);
    const joined = new Uint8Array(size);
    let offset = 0;
    for (const c of all) {
      joined.set(c, offset);
      offset += c.length;
    }
    expect(sha256Of(joined)).toBe(sha256Of(pattern(size)));
  });

  it('progress ends at the total', async () => {
    const reports: Array<[number, number]> = [];
    const d = await client.queries.blob({ size: 500000 }, (r, t) => reports.push([r, t]));
    await d.bytes();
    expect(reports[reports.length - 1]).toEqual([500000, 500000]);
    for (let i = 1; i < reports.length; i++) {
      expect(reports[i][0]).toBeGreaterThanOrEqual(reports[i - 1][0]);
    }
  });

  it('an empty download', async () => {
    const d = await client.queries.blob({ size: 0 });
    expect((await d.bytes()).length).toBe(0);
  });

  it('a missing resource is a RestError, not a download', async () => {
    const failure = await client.queries.avatar({ id: 'p1' }).catch((e: unknown) => e);
    expect(failure).toBeInstanceOf(RestError);
    expect((failure as RestError).status).toBe(404);
  });

  it('an upload and the matching download round-trip, with the stored mime type', async () => {
    const bytes = pattern(70000);
    await client.mutations.uploadAvatar({ id: 'p1', file: uploadOf(bytes, { mimeType: 'image/png' }) });
    const d = await client.queries.avatar({ id: 'p1' });
    expect(d.contentType).toMatch(/^image\/png/);
    expect(d.filename).toBe('p1.png');
    expect(await d.bytes()).toEqual(bytes);
  });

  it('a nullable download is null on 204 and present afterwards', async () => {
    expect(await client.queries.avatarOrEmpty({ id: 'p1' })).toBeNull();
    await client.mutations.uploadAvatar({ id: 'p1', file: uploadOf(pattern(10)) });
    expect(await (await client.queries.avatarOrEmpty({ id: 'p1' }))!.bytes()).toEqual(pattern(10));
  });

  it('several downloads can be open at once', async () => {
    const downloads = await Promise.all([1, 2, 3, 4, 5].map((i) => client.queries.blob({ size: i * 1000 })));
    const bytes = await Promise.all(downloads.map((d) => d.bytes()));
    expect(bytes.map((b) => b.length)).toEqual([1000, 2000, 3000, 4000, 5000]);
  });
});
