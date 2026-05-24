import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import type { GLUpload } from '../lib/generated/client/graph-link-uploads.js';
import { MockAdapter, MockMultipartAdapter, MockWsAdapter } from './mock-adapter.ts';
import { kUserAliceJson } from './fixtures.ts';

function makeFile(bytes: number[], filename = 'test.png'): GLUpload {
  return {
    stream: new Blob([new Uint8Array(bytes)]),
    length: bytes.length,
    filename,
    mimeType: 'image/png',
  };
}

let adapter: MockAdapter;
let multipart: MockMultipartAdapter;
let client: GraphLinkClient;

beforeEach(() => {
  adapter = new MockAdapter();
  multipart = new MockMultipartAdapter();
  client = new GraphLinkClient(adapter.call, new MockWsAdapter(), multipart.call);
});

// ── uploadOneFile ─────────────────────────────────────────────────────────────

describe('uploadOneFile — single file', () => {
  beforeEach(() => {
    multipart.registerData('uploadOneFile', { uploadOneFile: kUserAliceJson });
  });

  it('response deserialized: id correct', async () => {
    const res = await client.mutations.uploadOneFile({ userId: 'user-1', file: makeFile([1, 2, 3]) });
    expect(res.uploadOneFile.id).toBe('user-1');
  });

  it('response deserialized: name correct', async () => {
    const res = await client.mutations.uploadOneFile({ userId: 'user-1', file: makeFile([1, 2, 3]) });
    expect(res.uploadOneFile.name).toBe('Alice Smith');
  });

  it('multipart adapter is called once', async () => {
    await client.mutations.uploadOneFile({ userId: 'user-1', file: makeFile([1, 2, 3]) });
    expect(multipart.callCount).toBe(1);
  });

  it('userId variable is in operations payload', async () => {
    await client.mutations.uploadOneFile({ userId: 'user-42', file: makeFile([1, 2, 3]) });
    const ops = JSON.parse(multipart.lastCall!.parts['operations'] as string);
    expect(ops.variables.userId).toBe('user-42');
  });

  it('file variable is null in operations (multipart spec)', async () => {
    await client.mutations.uploadOneFile({ userId: 'user-1', file: makeFile([1, 2, 3]) });
    const ops = JSON.parse(multipart.lastCall!.parts['operations'] as string);
    expect(ops.variables.file).toBeNull();
  });

  it('map slot 0 points to variables.file', async () => {
    await client.mutations.uploadOneFile({ userId: 'user-1', file: makeFile([1, 2, 3]) });
    const map = JSON.parse(multipart.lastCall!.parts['map'] as string);
    expect(map['0']).toEqual(['variables.file']);
  });

  it('file part is present under slot key "0"', async () => {
    await client.mutations.uploadOneFile({ userId: 'user-1', file: makeFile([1, 2, 3]) });
    expect(multipart.lastCall!.parts['0']).toBeDefined();
  });

  it('regular JSON adapter is not called', async () => {
    await client.mutations.uploadOneFile({ userId: 'user-1', file: makeFile([1, 2, 3]) });
    expect(adapter.callCount).toBe(0);
  });
});

// ── uploadFileList ────────────────────────────────────────────────────────────

describe('uploadFileList — list of files', () => {
  beforeEach(() => {
    multipart.registerData('uploadFileList', { uploadFileList: kUserAliceJson });
  });

  it('response deserialized: id correct', async () => {
    const res = await client.mutations.uploadFileList({
      userId: 'user-1',
      files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])],
    });
    expect(res.uploadFileList.id).toBe('user-1');
  });

  it('files variables are all null in operations (multipart spec)', async () => {
    await client.mutations.uploadFileList({
      userId: 'user-1',
      files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])],
    });
    const ops = JSON.parse(multipart.lastCall!.parts['operations'] as string);
    expect(ops.variables.files).toEqual([null, null]);
  });

  it('map slot 0 points to variables.files.0', async () => {
    await client.mutations.uploadFileList({
      userId: 'user-1',
      files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])],
    });
    const map = JSON.parse(multipart.lastCall!.parts['map'] as string);
    expect(map['0']).toEqual(['variables.files.0']);
  });

  it('map slot 1 points to variables.files.1', async () => {
    await client.mutations.uploadFileList({
      userId: 'user-1',
      files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])],
    });
    const map = JSON.parse(multipart.lastCall!.parts['map'] as string);
    expect(map['1']).toEqual(['variables.files.1']);
  });

  it('both file parts present in parts map', async () => {
    await client.mutations.uploadFileList({
      userId: 'user-1',
      files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])],
    });
    expect(multipart.lastCall!.parts['0']).toBeDefined();
    expect(multipart.lastCall!.parts['1']).toBeDefined();
  });

  it('single-file list produces exactly one slot in map', async () => {
    await client.mutations.uploadFileList({ userId: 'user-1', files: [makeFile([1, 2, 3])] });
    const map = JSON.parse(multipart.lastCall!.parts['map'] as string);
    expect(Object.keys(map)).toHaveLength(1);
  });
});
