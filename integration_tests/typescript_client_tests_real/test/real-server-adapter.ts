import { GraphLinkClient, DefaultGraphLinkWsAdapter } from '../lib/generated/client/graph-link-client.js';
import type { GLUpload, GLMultipartAdapter, UploadProgressCallback } from '../lib/generated/client/graph-link-uploads.js';

const HTTP_URL = 'http://localhost:9999/graphql';
const UPLOAD_URL = 'http://localhost:9998/graphql';
export const WS_URL = 'ws://localhost:9999/graphql';

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
