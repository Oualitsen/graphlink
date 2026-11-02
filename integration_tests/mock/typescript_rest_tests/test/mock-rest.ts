import { GraphLinkClient, RestResponse, restReadAll, type RestRequest } from '../lib/generated/graphlink';

type Responder = () => RestResponse;

export class MockRest {
  readonly calls: RestRequest[] = [];
  readonly bodies: string[] = [];
  failTransport = false;
  private readonly responses = new Map<string, Responder>();

  on(
    method: string,
    path: string,
    options: { status?: number; json?: unknown; text?: string; headers?: Record<string, string> } = {},
  ): void {
    const text = options.text ?? (options.json === undefined ? '' : JSON.stringify(options.json));
    this.responses.set(`${method} ${path}`, () => RestResponse.fromText(options.status ?? 200, text, options.headers ?? {}));
  }

  get last(): RestRequest {
    return this.calls[this.calls.length - 1];
  }

  call = async (request: RestRequest): Promise<RestResponse> => {
    if (this.failTransport) throw new Error('offline');
    this.calls.push(request);
    const body = request.body;
    if (body?.kind === 'json') {
      this.bodies.push(body.json);
    } else if (body?.kind === 'raw') {
      this.bodies.push(new TextDecoder().decode(await restReadAll(body.upload.stream)));
    }
    const response = this.responses.get(`${request.method} ${request.path}`);
    if (response === undefined) return RestResponse.fromText(404, 'no mock');
    return response();
  };
}

export const q = (r: RestRequest): string => r.query.map(([k, v]) => `${k}=${v}`).join('&');

export const clientFor = (rest: MockRest): GraphLinkClient =>
  new GraphLinkClient(async () => '{"data":{"ping":"pong"}}', rest.call);

export const bytesUpload = (text: string, options: { filename?: string; mimeType?: string } = {}) => {
  const bytes = new TextEncoder().encode(text);
  return {
    stream: new Blob([bytes]),
    length: bytes.length,
    filename: options.filename,
    mimeType: options.mimeType ?? 'application/octet-stream',
  };
};
