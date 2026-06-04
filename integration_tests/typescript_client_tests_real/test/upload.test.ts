import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import type { GLUpload } from '../lib/generated/client/graph-link-uploads.js';
import { newUploadClient } from './real-server-adapter.ts';

function makeFile(bytes: number[], name = 'test.png'): GLUpload {
  return {
    stream: new Blob([new Uint8Array(bytes)], { type: 'image/png' }),
    length: bytes.length,
    filename: name,
    mimeType: 'image/png',
  };
}

let client: GraphLinkClient;
beforeEach(() => { client = newUploadClient(); });

// ── uploadOneFile ──────────────────────────────────────────────────────────────

describe('uploadOneFile', () => {
  it('returns true when file is provided', async () => {
    const res = await client.mutations.uploadOneFile({ userId: 'user-1', file: makeFile([1, 2, 3]) });
    expect(res.uploadOneFile).toBe(true);
  });

  it('returns true for a different userId', async () => {
    const res = await client.mutations.uploadOneFile({ userId: 'user-42', file: makeFile([10, 20, 30]) });
    expect(res.uploadOneFile).toBe(true);
  });

  it('returns true for a larger file', async () => {
    const bytes = Array.from({ length: 1024 }, (_, i) => i % 256);
    const res = await client.mutations.uploadOneFile({ userId: 'user-1', file: makeFile(bytes, 'big.bin') });
    expect(res.uploadOneFile).toBe(true);
  });
});

// ── uploadFileList ─────────────────────────────────────────────────────────────

describe('uploadFileList', () => {
  it('returns true for a single file in the list', async () => {
    const res = await client.mutations.uploadFileList({ userId: 'user-1', files: [makeFile([1, 2, 3])] });
    expect(res.uploadFileList).toBe(true);
  });

  it('returns true for two files', async () => {
    const res = await client.mutations.uploadFileList({
      userId: 'user-1',
      files: [makeFile([1, 2, 3]), makeFile([4, 5, 6], 'second.png')],
    });
    expect(res.uploadFileList).toBe(true);
  });

  it('returns true for three files', async () => {
    const res = await client.mutations.uploadFileList({
      userId: 'user-2',
      files: [makeFile([1]), makeFile([2]), makeFile([3])],
    });
    expect(res.uploadFileList).toBe(true);
  });
});
