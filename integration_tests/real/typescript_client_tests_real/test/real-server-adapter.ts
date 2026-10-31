import { execSync, spawn } from 'node:child_process';
import { createConnection } from 'node:net';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import type { GLUpload, GLMultipartAdapter, UploadProgressCallback } from '../lib/generated/client/graph-link-uploads.js';
import { DefaultGraphLinkWsAdapter } from '../lib/generated/graphlink.js';


const HTTP_URL = 'http://localhost:9988/graphql';
const UPLOAD_URL = 'http://localhost:9998/graphql';
export const WS_URL = 'ws://localhost:9988/graphql';

export function httpUrlForPort(port: number): string {
  return `http://localhost:${port}/graphql`;
}

export function wsUrlForPort(port: number): string {
  return `ws://localhost:${port}/graphql`;
}

export function httpAdapterForPort(port: number) {
  return async (payload: string): Promise<string> => {
    const response = await fetch(httpUrlForPort(port), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: payload,
    });
    return response.text();
  };
}

export function newWsAdapterForPort(port: number): DefaultGraphLinkWsAdapter {
  return new DefaultGraphLinkWsAdapter(wsUrlForPort(port));
}

/** Adapter with maxReconnectAttempts=null (retry forever) and maxReconnectDelay=2s. */
export function newWsAdapterNeverStop(port: number): DefaultGraphLinkWsAdapter {
  return new DefaultGraphLinkWsAdapter(wsUrlForPort(port), undefined, null, 2_000);
}

// ---------------------------------------------------------------------------
// Server lifecycle utilities
// ---------------------------------------------------------------------------

const JAR_PATH = new URL('../../spring_server/build/libs/graphlink-test-server-0.0.1.jar', import.meta.url).pathname;

export function killPort(port: number): void {
  try {
    execSync(`lsof -ti :${port} -sTCP:LISTEN | xargs kill -9 2>/dev/null || true`, { shell: '/bin/bash' });
  } catch { /* ignore */ }
}

function waitForPort(port: number, timeoutMs = 30_000): Promise<void> {
  return new Promise((resolve, reject) => {
    const deadline = Date.now() + timeoutMs;
    function attempt() {
      const sock = createConnection(port, 'localhost');
      sock.once('connect', () => { sock.destroy(); resolve(); });
      sock.once('error', () => {
        sock.destroy();
        if (Date.now() >= deadline) { reject(new Error(`Port ${port} did not open within ${timeoutMs}ms`)); return; }
        setTimeout(attempt, 500);
      });
    }
    attempt();
  });
}

export async function startServer(port: number): Promise<void> {
  killPort(port);
  const proc = spawn('java', ['-jar', JAR_PATH, `--server.port=${port}`, '--management.server.port=-1'], { stdio: 'ignore', detached: true });
  proc.unref();
  await waitForPort(port);
}

export async function realHttpAdapter(payload: string): Promise<string> {
  const response = await fetch(HTTP_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: payload,
  });
  return response.text();
}

export const realMultipartAdapter: GLMultipartAdapter = async (
  parts: Record<string, unknown>,
  _onProgress?: UploadProgressCallback,
): Promise<string> => {
  const formData = new FormData();
  for (const [key, value] of Object.entries(parts)) {
    if (typeof value === 'string') {
      formData.append(key, value);
    } else {
      const upload = value as GLUpload;
      const blob =
        upload.stream instanceof Blob
          ? upload.stream
          : new Blob([await new Response(upload.stream as ReadableStream).arrayBuffer()], {
              type: upload.mimeType,
            });
      formData.append(key, blob, upload.filename ?? 'upload');
    }
  }
  const response = await fetch(UPLOAD_URL, { method: 'POST', body: formData });
  return response.text();
};

export function newWsAdapter(): DefaultGraphLinkWsAdapter {
  return new DefaultGraphLinkWsAdapter(WS_URL);
}

export function newClient(): GraphLinkClient {
  return new GraphLinkClient(realHttpAdapter, newWsAdapter());
}

export function newUploadClient(): GraphLinkClient {
  return new GraphLinkClient(realHttpAdapter, newWsAdapter(), realMultipartAdapter);
}
