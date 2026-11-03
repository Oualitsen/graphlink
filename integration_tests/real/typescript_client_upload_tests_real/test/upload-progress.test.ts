import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client';
import { createFetchAdapter, createMultipartFetchAdapter } from '../lib/generated/client/graph-link-adapters';
import type { GLUpload } from '../lib/generated/client/graph-link-uploads';
import { part, RecordingServer, sha256Of } from './recording-server';

function pattern(size: number): Uint8Array {
  const bytes = new Uint8Array(size);
  for (let i = 0; i < size; i++) bytes[i] = (i * 31 + 7) % 251;
  return bytes;
}

function fileOf(bytes: Uint8Array, filename: string, knownLength = true, chunk = 65536): GLUpload {
  let offset = 0;
  return {
    stream: new ReadableStream<Uint8Array>({
      pull(controller) {
        if (offset >= bytes.length) {
          controller.close();
          return;
        }
        controller.enqueue(bytes.slice(offset, offset + chunk));
        offset += chunk;
      },
    }),
    length: knownLength ? bytes.length : undefined,
    filename,
    mimeType: 'application/octet-stream',
  };
}

describe('GraphQL multipart uploads', () => {
  let server: RecordingServer;
  let client: GraphLinkClient;

  beforeEach(async () => {
    server = await RecordingServer.start();
    client = new GraphLinkClient(createFetchAdapter(server.url), createMultipartFetchAdapter(server.url));
  });
  afterEach(() => server.close());

  it('a 6 MB file arrives intact without progress', async () => {
    const bytes = pattern(6 * 1024 * 1024);
    const res = await client.mutations.uploadOneFile({ userId: 'u1', file: fileOf(bytes, 'big.bin') });
    expect(res.uploadOneFile).toBe(true);
    const sent = server.only();
    expect(sha256Of(part(sent, '0').bytes)).toBe(sha256Of(bytes));
    expect(part(sent, '0').filename).toBe('big.bin');
    expect(part(sent, 'operations').bytes.toString()).toContain('"userId":"u1"');
  });

  it('a file of known length is sent with a content-length', async () => {
    const bytes = pattern(300000);
    await client.mutations.uploadOneFile({ userId: 'u1', file: fileOf(bytes, 'a.bin') });
    const sent = server.only();
    expect(sent.chunked).toBe(false);
    expect(sent.contentLength).toBeGreaterThan(bytes.length);
  });

  it('a file of unknown length arrives intact, sent chunked', async () => {
    const bytes = pattern(300000);
    await client.mutations.uploadOneFile({ userId: 'u1', file: fileOf(bytes, 'a.bin', false) });
    const sent = server.only();
    expect(sha256Of(part(sent, '0').bytes)).toBe(sha256Of(bytes));
    expect(sent.chunked).toBe(true);
  });

  it('a 6 MB file arrives intact with progress', async () => {
    const bytes = pattern(6 * 1024 * 1024);
    await client.mutations.uploadOneFile({ userId: 'u1', file: fileOf(bytes, 'big.bin') }, () => {});
    expect(sha256Of(part(server.only(), '0').bytes)).toBe(sha256Of(bytes));
  });

  it('progress increases and ends at the total, which is the content-length', async () => {
    const bytes = pattern(6 * 1024 * 1024);
    const reports: Array<[number, number]> = [];
    await client.mutations.uploadOneFile({ userId: 'u1', file: fileOf(bytes, 'big.bin') }, (s, t) => reports.push([s, t]));
    expect(reports.length).toBeGreaterThan(10);
    for (let i = 1; i < reports.length; i++) expect(reports[i]![0]).toBeGreaterThanOrEqual(reports[i - 1]![0]);
    const last = reports[reports.length - 1]!;
    expect(last[0]).toBe(last[1]);
    expect(last[1]).toBeGreaterThan(bytes.length);
    expect(last[1]).toBe(server.only().contentLength);
  });

  it('the file is not read in full before the first progress report', async () => {
    const bytes = pattern(6 * 1024 * 1024);
    const chunk = 65536;
    let offset = 0;
    let pulled = 0;
    let pulledAtFirstReport = -1;
    const slow = new ReadableStream<Uint8Array>({
      async pull(controller) {
        if (offset >= bytes.length) {
          controller.close();
          return;
        }
        if (offset % (256 * 1024) === 0) await new Promise((resolve) => setTimeout(resolve, 2));
        controller.enqueue(bytes.slice(offset, offset + chunk));
        offset += chunk;
        pulled = offset;
      },
    });
    await client.mutations.uploadOneFile(
      { userId: 'u1', file: { stream: slow, length: bytes.length, filename: 'big.bin', mimeType: 'application/octet-stream' } },
      () => {
        if (pulledAtFirstReport < 0) pulledAtFirstReport = pulled;
      },
    );
    expect(pulledAtFirstReport).toBeGreaterThanOrEqual(0);
    expect(pulledAtFirstReport).toBeLessThan(bytes.length);
  });

  it('a file of unknown length fires no progress and arrives intact', async () => {
    const bytes = pattern(300000);
    let calls = 0;
    await client.mutations.uploadOneFile({ userId: 'u1', file: fileOf(bytes, 'a.bin', false) }, () => calls++);
    const sent = server.only();
    expect(sha256Of(part(sent, '0').bytes)).toBe(sha256Of(bytes));
    expect(sent.chunked).toBe(true);
    expect(calls).toBe(0);
  });

  it('two files arrive intact in slot order, with progress', async () => {
    const a = pattern(1200000);
    const b = pattern(900000).reverse();
    const reports: Array<[number, number]> = [];
    const res = await client.mutations.uploadFileList(
      { userId: 'u1', files: [fileOf(a, 'a.bin'), fileOf(b, 'b.bin')] },
      (s, t) => reports.push([s, t]),
    );
    expect(res.uploadFileList).toBe(true);
    const sent = server.only();
    expect(sha256Of(part(sent, '0').bytes)).toBe(sha256Of(a));
    expect(part(sent, '0').filename).toBe('a.bin');
    expect(sha256Of(part(sent, '1').bytes)).toBe(sha256Of(b));
    expect(part(sent, '1').filename).toBe('b.bin');
    const last = reports[reports.length - 1]!;
    expect(last[0]).toBe(last[1]);
  });
});

const springUrl = process.env['UPLOAD_SERVER_URL'];

describe.skipIf(springUrl === undefined || springUrl === '')('against the Spring upload server', () => {
  const spring = new GraphLinkClient(createFetchAdapter(springUrl ?? ''), createMultipartFetchAdapter(springUrl ?? ''));

  it('accepts a file of known length', async () => {
    const res = await spring.mutations.uploadOneFile({ userId: 'u1', file: fileOf(pattern(3_000_000), 'f.bin') }, () => {});
    expect(res.uploadOneFile).toBe(true);
  });

  it('accepts a file of unknown length, chunked', async () => {
    const res = await spring.mutations.uploadOneFile({ userId: 'u1', file: fileOf(pattern(3_000_000), 'f.bin', false) });
    expect(res.uploadOneFile).toBe(true);
  });

  it('accepts a list of files', async () => {
    const res = await spring.mutations.uploadFileList({
      userId: 'u1',
      files: [fileOf(pattern(1000), 'a.bin'), fileOf(pattern(2000), 'b.bin', false)],
    });
    expect(res.uploadFileList).toBe(true);
  });
});
