import { beforeEach, describe, expect, it } from 'vitest';
import type { GLUpload, GraphLinkClient } from '../lib/generated/graphlink';
import { variant } from './variant';
import { header, newClient, pattern, resetServer, sha256Of, uploadOf } from './support';

let client: GraphLinkClient;

beforeEach(async () => {
  await resetServer();
  client = newClient();
});

describe('raw body', () => {
  it('is exactly the file bytes with the upload mime type and a known length', async () => {
    const bytes = pattern(120000);
    const e = await client.mutations.eRaw({ file: uploadOf(bytes, { mimeType: 'image/png' }) });
    expect(e.method).toBe('PUT');
    expect(e.contentType).toMatch(/^image\/png/);
    expect(e.bodySize).toBe(bytes.length);
    expect(e.bodySha256).toBe(sha256Of(bytes));
    expect(e.contentLength).toBe(bytes.length);
    expect(e.chunked).toBe(false);
  });

  it('an upload of unknown length is streamed chunked', async () => {
    const bytes = pattern(250000);
    const e = await client.mutations.eRaw({ file: uploadOf(bytes, { knownLength: false }) });
    if (variant.adapter !== 'axios') {
      expect(e.chunked).toBe(true);
      expect(e.contentLength).toBeNull();
    }
    expect(e.bodySha256).toBe(sha256Of(bytes));
  });

  it('the default mime type is application/octet-stream', async () => {
    const e = await client.mutations.eRaw({ file: uploadOf(pattern(5)) });
    expect(e.contentType).toMatch(/^application\/octet-stream/);
  });

  it('contentType on the operation replaces the upload mime type', async () => {
    const e = await client.mutations.eRawType({ file: uploadOf(pattern(5), { mimeType: 'image/png' }) });
    expect(e.contentType).toMatch(/^application\/x-custom/);
  });

  it('an empty file is an empty body', async () => {
    const e = await client.mutations.eRaw({ file: uploadOf(new Uint8Array(0)) });
    expect(e.bodySize).toBe(0);
  });

  it('a null optional file means no body and no Content-Type', async () => {
    const e = await client.mutations.eRawOptional({});
    expect(e.bodySize).toBe(0);
    expect(e.contentType).toBeNull();
  });

  it('the filename is not sent', async () => {
    const e = await client.mutations.eRaw({ file: uploadOf(pattern(5), { filename: 'secret-name.bin' }) });
    expect(e.headers.map((h) => h.value).join('|')).not.toContain('secret-name');
    expect(e.path).not.toContain('secret-name');
    expect(header(e, 'content-disposition')).toBeUndefined();
  });

  it('a multi-megabyte upload arrives intact and progress ends at the total', async () => {
    const bytes = pattern(6 * 1024 * 1024);
    const reports: Array<[number, number]> = [];
    const e = await client.mutations.eRaw({ file: uploadOf(bytes) }, (sent, total) => reports.push([sent, total]));
    expect(e.bodySha256).toBe(sha256Of(bytes));
    expect(reports[reports.length - 1]).toEqual([bytes.length, bytes.length]);
    for (let i = 1; i < reports.length; i++) {
      expect(reports[i][0]).toBeGreaterThanOrEqual(reports[i - 1][0]);
    }
  });

  it('progress is not reported when the length is unknown', async () => {
    const reports: Array<[number, number]> = [];
    await client.mutations.eRaw({ file: uploadOf(pattern(40000), { knownLength: false }) }, (s, t) => reports.push([s, t]));
    expect(reports).toHaveLength(0);
  });

  it('a stream that fails mid-way fails the call and does not hang', async () => {
    let sent = false;
    const failing: GLUpload = {
      stream: new ReadableStream<Uint8Array>({
        pull(controller) {
          if (!sent) {
            sent = true;
            controller.enqueue(pattern(1000));
          } else {
            controller.error(new Error('source failed'));
          }
        },
      }),
      mimeType: 'application/octet-stream',
    };
    await expect(client.mutations.eRaw({ file: failing })).rejects.toBeDefined();
    expect((await client.queries.eAccept()).method).toBe('GET');
  });
});
