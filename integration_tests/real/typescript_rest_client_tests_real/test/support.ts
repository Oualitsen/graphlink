import { createHash } from 'node:crypto';
import {
  GraphLinkClient,
  createFetchAdapter,
  type Echo,
  type GLUpload,
  type GraphLinkCacheStore,
  type Pair,
  type Part,
} from '../lib/generated/graphlink';
import { variant } from './variant';
import { createAdapter } from './rest-adapter';

export const serverUrl = `http://127.0.0.1:${variant.port}`;

export function newClient(options: {
  baseUrl?: string;
  headers?: () => Promise<Record<string, string>>;
  store?: GraphLinkCacheStore;
} = {}): GraphLinkClient {
  const base = options.baseUrl ?? serverUrl;
  return new GraphLinkClient(
    createFetchAdapter(`${base}/graphql`),
    createAdapter(base, options.headers),
    options.store,
  );
}

export async function resetServer(): Promise<void> {
  await fetch(`${serverUrl}/_reset`, { method: 'POST' });
}

export const pair = (p: Pair): string => `${p.name}=${p.value}`;

export const queryPairs = (e: Echo): string[] => e.query.map(pair);

export const formPairs = (e: Echo): string[] => e.form.map(pair);

export function header(e: Echo, name: string): string | undefined {
  return e.headers.find((h) => h.name === name.toLowerCase())?.value;
}

export function part(e: Echo, name: string): Part {
  const found = e.parts.find((p) => p.name === name);
  if (found === undefined) throw new Error(`no part named ${name}`);
  return found;
}

export const partsNamed = (e: Echo, name: string): Part[] => e.parts.filter((p) => p.name === name);

export const queryValue = (e: Echo, name: string): string | undefined => e.query.find((p) => p.name === name)?.value;

export const formValue = (e: Echo, name: string): string | undefined => e.form.find((p) => p.name === name)?.value;

export const bodyJson = (e: Echo): unknown => JSON.parse(e.bodyText!);

export function pattern(size: number): Uint8Array {
  const out = new Uint8Array(size);
  for (let i = 0; i < size; i++) out[i] = i % 251;
  return out;
}

export const sha256Of = (bytes: Uint8Array): string => createHash('sha256').update(bytes).digest('hex');

export function uploadOf(
  bytes: Uint8Array,
  options: { filename?: string; mimeType?: string; knownLength?: boolean } = {},
): GLUpload {
  const chunkSize = 16384;
  let offset = 0;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      if (offset >= bytes.length) {
        controller.close();
        return;
      }
      controller.enqueue(bytes.slice(offset, offset + chunkSize));
      offset += chunkSize;
    },
  });
  return {
    stream,
    length: options.knownLength === false ? undefined : bytes.length,
    filename: options.filename,
    mimeType: options.mimeType ?? 'application/octet-stream',
  };
}

export async function collect(stream: ReadableStream<Uint8Array>): Promise<Uint8Array> {
  const chunks: Uint8Array[] = [];
  const reader = stream.getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
  }
  const out = new Uint8Array(chunks.reduce((n, c) => n + c.length, 0));
  let offset = 0;
  for (const c of chunks) {
    out.set(c, offset);
    offset += c.length;
  }
  return out;
}
