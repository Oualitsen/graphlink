import { createHash } from 'node:crypto';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';

export function sha256Of(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex');
}

export interface ReceivedPart {
  name: string;
  filename: string | undefined;
  contentType: string | undefined;
  bytes: Buffer;
}

export interface Received {
  contentLength: number | undefined;
  chunked: boolean;
  parts: ReceivedPart[];
}

export function part(received: Received, name: string): ReceivedPart {
  const found = received.parts.find((p) => p.name === name);
  if (found === undefined) throw new Error(`no part named ${name}`);
  return found;
}

/** GraphQL endpoint that records every multipart request as it arrived on the wire. */
export class RecordingServer {
  readonly requests: Received[] = [];
  private constructor(private readonly server: Server) {}

  static async start(): Promise<RecordingServer> {
    let recording!: RecordingServer;
    const server = createServer((request, response) => {
      const chunks: Buffer[] = [];
      request.on('data', (chunk: Buffer) => chunks.push(chunk));
      request.on('end', () => {
        const body = Buffer.concat(chunks);
        const boundary = /boundary=([^;]+)/.exec(request.headers['content-type'] ?? '')?.[1];
        const length = request.headers['content-length'];
        recording.requests.push({
          contentLength: length === undefined ? undefined : Number(length),
          chunked: (request.headers['transfer-encoding'] ?? '').toLowerCase().includes('chunked'),
          parts: boundary === undefined ? [] : parse(body, boundary),
        });
        response.setHeader('Content-Type', 'application/json');
        response.end('{"data":{"uploadOneFile":true,"uploadFileList":true}}');
      });
    });
    recording = new RecordingServer(server);
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    return recording;
  }

  get url(): string {
    return `http://127.0.0.1:${(this.server.address() as AddressInfo).port}/graphql`;
  }

  only(): Received {
    if (this.requests.length !== 1) throw new Error(`expected one request, got ${this.requests.length}`);
    return this.requests[0]!;
  }

  close(): Promise<void> {
    return new Promise((resolve) => this.server.close(() => resolve()));
  }
}

function parse(body: Buffer, boundary: string): ReceivedPart[] {
  const delimiter = Buffer.from(`--${boundary}`);
  const starts: number[] = [];
  for (let at = body.indexOf(delimiter); at >= 0; at = body.indexOf(delimiter, at + delimiter.length)) starts.push(at);
  const parts: ReceivedPart[] = [];
  for (let i = 0; i < starts.length - 1; i++) {
    const from = starts[i]! + delimiter.length + 2;
    const to = starts[i + 1]! - 2;
    const headerEnd = body.indexOf('\r\n\r\n', from);
    const headers = body.subarray(from, headerEnd).toString('utf8');
    const disposition = /name="([^"]*)"(?:; filename="([^"]*)")?/.exec(headers)!;
    parts.push({
      name: disposition[1]!,
      filename: disposition[2],
      contentType: /content-type: ([^\r\n]+)/i.exec(headers)?.[1],
      bytes: body.subarray(headerEnd + 4, to),
    });
  }
  return parts;
}
