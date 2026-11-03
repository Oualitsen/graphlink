const tsRestFile = r'''
export type GLRestAdapter = (request: RestRequest) => Promise<RestResponse>;

export type RestBody =
  | { kind: 'json'; json: string }
  | { kind: 'form'; fields: Array<[string, string]> }
  | { kind: 'multipart'; parts: RestPart[] }
  | { kind: 'raw'; upload: GLUpload };

export interface RestPart {
  name: string;
  value?: string;
  file?: GLUpload;
  mimeType?: string;
}

export interface RestRequest {
  method: string;
  path: string;
  query: Array<[string, string]>;
  headers: Record<string, string>;
  body?: RestBody;
  onSendProgress?: UploadProgressCallback;
}

export type DownloadProgressCallback = (received: number, total: number) => void;

export interface RestOptions {
  bracket?: boolean;
  comma?: boolean;
}

export async function restReadAll(source: ReadableStream<Uint8Array> | Blob): Promise<Uint8Array> {
  if (typeof (source as Blob).arrayBuffer === 'function') {
    return new Uint8Array(await (source as Blob).arrayBuffer());
  }
  const reader = (source as ReadableStream<Uint8Array>).getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    size += value.length;
  }
  const out = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

export class RestResponse {
  constructor(
    readonly status: number,
    readonly stream: ReadableStream<Uint8Array>,
    readonly headers: Record<string, string> = {},
  ) {}

  static fromBytes(status: number, bytes: Uint8Array, headers: Record<string, string> = {}): RestResponse {
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        if (bytes.length > 0) controller.enqueue(bytes);
        controller.close();
      },
    });
    return new RestResponse(status, stream, headers);
  }

  static fromText(status: number, text: string, headers: Record<string, string> = {}): RestResponse {
    return RestResponse.fromBytes(status, new TextEncoder().encode(text), headers);
  }

  get isSuccess(): boolean {
    return this.status >= 200 && this.status < 300;
  }

  bytes(): Promise<Uint8Array> {
    return restReadAll(this.stream);
  }

  async text(): Promise<string> {
    return new TextDecoder().decode(await this.bytes());
  }

  async json(): Promise<unknown> {
    const body = await this.text();
    return body.length === 0 ? null : JSON.parse(body);
  }

  async drain(): Promise<void> {
    await this.bytes();
  }
}

export class RestError extends Error {
  constructor(
    readonly status: number,
    readonly headers: Record<string, string>,
    readonly body: string,
  ) {
    super(`RestError(${status}): ${body}`);
    this.name = 'RestError';
  }

  static async from(response: RestResponse): Promise<RestError> {
    return new RestError(response.status, response.headers, await response.text());
  }
}

export class GLDownload {
  constructor(
    readonly stream: ReadableStream<Uint8Array>,
    readonly filename?: string,
    readonly contentType?: string,
    readonly length?: number,
  ) {}

  static fromResponse(response: RestResponse, onProgress?: DownloadProgressCallback): GLDownload {
    const header = (name: string): string | undefined => {
      for (const [key, value] of Object.entries(response.headers)) {
        if (key.toLowerCase() === name) return value;
      }
      return undefined;
    };
    const parsedLength = parseInt(header('content-length') ?? '', 10);
    const length = Number.isNaN(parsedLength) ? undefined : parsedLength;
    let received = 0;
    const stream = onProgress === undefined
      ? response.stream
      : response.stream.pipeThrough(new TransformStream<Uint8Array, Uint8Array>({
          transform(chunk, controller) {
            received += chunk.length;
            onProgress(received, length ?? -1);
            controller.enqueue(chunk);
          },
        }));
    const disposition = header('content-disposition');
    const match = disposition === undefined ? null : /filename\*?=(?:UTF-8'')?"?([^";]+)"?/i.exec(disposition);
    let filename: string | undefined;
    if (match !== null) {
      try {
        filename = decodeURIComponent(match[1]);
      } catch {
        filename = match[1];
      }
    }
    return new GLDownload(stream, filename, header('content-type'), length);
  }

  bytes(): Promise<Uint8Array> {
    return restReadAll(this.stream);
  }
}

export function glNoGraphQL__(): Promise<string> {
  return Promise.reject(new Error('This schema has no GraphQL operation: pass no GraphQL adapter'));
}

export function restEncode(value: string): string {
  return encodeURIComponent(value).replace(/[!'()*]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase());
}

export function restEncodeQuery(value: string): string {
  return restEncode(value).replace(/%20/g, '+');
}

export function restUrl(baseUrl: string, request: RestRequest): string {
  const base = baseUrl.endsWith('/') ? baseUrl.slice(0, -1) : baseUrl;
  const query = request.query.map(([k, v]) => `${restEncodeQuery(k)}=${restEncodeQuery(v)}`).join('&');
  return `${base}${request.path}${query.length === 0 ? '' : '?' + query}`;
}

export function restFormBody(fields: Array<[string, string]>): string {
  return fields.map(([k, v]) => `${restEncodeQuery(k)}=${restEncodeQuery(v)}`).join('&');
}

export function restCountedStream(
  source: ReadableStream<Uint8Array> | Blob,
  total: number | undefined,
  onProgress: UploadProgressCallback | undefined,
): ReadableStream<Uint8Array> {
  return glUploadProgress(glUploadStream(source), total, onProgress);
}

function restText(value: unknown): string {
  return typeof value === 'string' ? value : String(value);
}

function restCollect(
  out: Array<[string, string]>,
  key: string,
  value: unknown,
  bracket: boolean,
  comma: boolean,
  inList: boolean,
): void {
  if (value === null || value === undefined) return;
  if (Array.isArray(value)) {
    const items = value.filter((e) => e !== null && e !== undefined);
    if (items.length === 0) return;
    if (!inList && items.every((e) => typeof e !== 'object')) {
      if (comma) {
        out.push([key, items.map(restText).join(',')]);
      } else {
        for (const e of items) out.push([key, restText(e)]);
      }
    } else {
      value.forEach((e, i) => restCollect(out, bracket ? `${key}[${i}]` : `${key}.${i}`, e, bracket, comma, true));
    }
  } else if (typeof value === 'object') {
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      restCollect(out, bracket ? `${key}[${k}]` : `${key}.${k}`, v, bracket, comma, false);
    }
  } else {
    out.push([key, restText(value)]);
  }
}

export function restEntries(key: string, value: unknown, options: RestOptions = {}): Array<[string, string]> {
  const out: Array<[string, string]> = [];
  restCollect(out, key, value, options.bracket ?? false, options.comma ?? false, false);
  return out;
}

export function restSpreadEntries(
  json: unknown,
  names: Record<string, string>,
  options: RestOptions = {},
): Array<[string, string]> {
  const out: Array<[string, string]> = [];
  if (json !== null && typeof json === 'object') {
    const record = json as Record<string, unknown>;
    for (const [field, wire] of Object.entries(names)) {
      restCollect(out, wire, record[field], options.bracket ?? false, options.comma ?? false, false);
    }
  }
  return out;
}

export function restHeaderValue(value: unknown): string {
  return Array.isArray(value)
    ? value.filter((e) => e !== null && e !== undefined).map(restText).join(',')
    : restText(value);
}

export function restHeader(name: string, value: unknown): Record<string, string> {
  return value === null || value === undefined ? {} : { [name]: restHeaderValue(value) };
}

export function restHeaders(json: unknown, names: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  if (json !== null && typeof json === 'object') {
    const record = json as Record<string, unknown>;
    for (const [field, header] of Object.entries(names)) {
      const value = record[field];
      if (value !== null && value !== undefined) out[header] = restHeaderValue(value);
    }
  }
  return out;
}

export function restParts(entries: Array<[string, string]>): RestPart[] {
  return entries.map(([name, value]) => ({ name, value }));
}

export function restNavigate(json: unknown, path: string[]): unknown {
  let current: unknown = json;
  for (const segment of path) {
    current = current !== null && typeof current === 'object' && !Array.isArray(current)
      ? (current as Record<string, unknown>)[segment]
      : null;
  }
  return current;
}
''';

const tsRestResolver = r'''
export class GraphLinkRestResolver extends GraphLinkResolverBase {
  restAdapter!: GLRestAdapter;

  protected async restCall__(request: RestRequest): Promise<RestResponse> {
    const response = await this.restAdapter(request);
    if (!response.isSuccess) throw await RestError.from(response);
    return response;
  }

  protected async restVoid__(request: RestRequest): Promise<void> {
    const response = await this.restCall__(request);
    await response.drain();
  }

  protected async restDownload__(
    request: RestRequest,
    allowEmpty: boolean,
    onProgress?: DownloadProgressCallback,
  ): Promise<GLDownload | null> {
    const response = await this.restCall__(request);
    if (response.status === 204) {
      await response.drain();
      if (allowEmpty) return null;
      throw new Error(`Empty REST response for a non-null download of ${request.method} ${request.path}`);
    }
    return GLDownload.fromResponse(response, onProgress);
  }

  protected async restText__(request: RestRequest): Promise<string> {
    return (await this.restCall__(request)).text();
  }

  protected async restTextOrNull__(request: RestRequest): Promise<string | null> {
    const text = await (await this.restCall__(request)).text();
    return text.length === 0 ? null : text;
  }

  protected async restJson__(request: RestRequest, path: string[], allowEmpty: boolean): Promise<unknown> {
    const json = restNavigate(await (await this.restCall__(request)).json(), path);
    if ((json === null || json === undefined) && !allowEmpty) {
      throw new Error(`Empty REST response for a non-null result of ${request.method} ${request.path}`);
    }
    return json ?? null;
  }

  protected async restCached__<T>(
    name: string,
    variables: Record<string, unknown>,
    ttl: number,
    tags: string[],
    staleIfOffline: boolean,
    fetch: () => Promise<unknown>,
    decode: (json: unknown) => T,
  ): Promise<T> {
    const key = GraphLinkPartialQuery.computeCacheKey(name, variables);
    const cached = await this._getFromCache(key, tags, staleIfOffline);
    if (cached !== null && !cached.stale) return decode(JSON.parse(cached.data));
    let json: unknown;
    try {
      json = await fetch();
    } catch (e) {
      if (e instanceof RestError) throw e;
      if (cached !== null) return decode(JSON.parse(cached.data));
      throw e;
    }
    const value = decode(json);
    if (json !== null && json !== undefined) {
      const entry = new GraphLinkCacheEntry(JSON.stringify(json), Date.now() + ttl * 1000);
      await this.gl_store__.set(key, JSON.stringify(entry.toJson()));
      if (tags.length > 0) await this._addKeyToTags(key, tags);
    }
    return value;
  }
}
''';

const tsRestFetchAdapter = r'''
export interface RestFetchAdapterOptions {
  fetchFn?: typeof fetch;
  headers?: () => Record<string, string> | Promise<Record<string, string>>;
}

export function createRestFetchAdapter(baseUrl: string, options?: RestFetchAdapterOptions): GLRestAdapter {
  return async (request: RestRequest): Promise<RestResponse> => {
    const fn = options?.fetchFn ?? globalThis.fetch;
    const headers: Record<string, string> = {
      ...(options?.headers ? await options.headers() : {}),
      ...request.headers,
    };
    const init: Record<string, unknown> = { method: request.method, headers };
    const body = request.body;
    if (body?.kind === 'json') {
      init.body = body.json;
    } else if (body?.kind === 'form') {
      init.body = restFormBody(body.fields);
    } else if (body?.kind === 'multipart') {
      const multipart = glFetchMultipart(body.parts, request.onSendProgress);
      Object.assign(headers, multipart.headers);
      init.body = multipart.body;
      if (multipart.duplex !== undefined) init.duplex = multipart.duplex;
    } else if (body?.kind === 'raw') {
      const upload = body.upload;
      if (upload.length !== undefined) headers['Content-Length'] = String(upload.length);
      if (request.onSendProgress === undefined && typeof (upload.stream as Blob).arrayBuffer === 'function') {
        init.body = upload.stream;
      } else {
        init.body = restCountedStream(upload.stream, upload.length, request.onSendProgress);
        init.duplex = 'half';
      }
    }
    const response = await fn(restUrl(baseUrl, request), init as RequestInit);
    const responseHeaders: Record<string, string> = {};
    response.headers.forEach((value, key) => {
      responseHeaders[key] = value;
    });
    const stream = response.body ?? new ReadableStream<Uint8Array>({ start: (c) => c.close() });
    return new RestResponse(response.status, stream, responseHeaders);
  };
}
''';

const tsRestAxiosAdapter = r'''
interface _RestAxiosLike {
  request(config: {
    method: string;
    url: string;
    headers: Record<string, string | false>;
    data?: unknown;
    responseType: 'arraybuffer';
    validateStatus: () => boolean;
    onUploadProgress?: (event: { loaded: number; total?: number }) => void;
  }): Promise<{ status: number; headers: Record<string, unknown>; data: ArrayBuffer | Uint8Array }>;
}

export interface RestAxiosAdapterOptions {
  headers?: () => Record<string, string> | Promise<Record<string, string>>;
}

function restIsNode(): boolean {
  const process = (globalThis as Record<string, unknown>)['process'] as { versions?: { node?: string } } | undefined;
  return process?.versions?.node !== undefined;
}

async function restNodeReadable(stream: ReadableStream<Uint8Array>): Promise<unknown> {
  const specifier = 'node:stream';
  const { Readable } = (await import(/* @vite-ignore */ specifier)) as { Readable: { fromWeb(stream: unknown): unknown } };
  return Readable.fromWeb(stream);
}

export function createRestAxiosAdapter(
  baseUrl: string,
  axiosInstance: _RestAxiosLike,
  options?: RestAxiosAdapterOptions,
): GLRestAdapter {
  return async (request: RestRequest): Promise<RestResponse> => {
    const headers: Record<string, string | false> = {
      ...(options?.headers ? await options.headers() : {}),
      ...request.headers,
    };
    let data: unknown;
    let browserProgress = false;
    const body = request.body;
    if (body === undefined && !Object.keys(headers).some((k) => k.toLowerCase() === 'content-type')) {
      headers['Content-Type'] = false;
    }
    if (body?.kind === 'json') {
      data = body.json;
    } else if (body?.kind === 'form') {
      data = restFormBody(body.fields);
    } else if (body?.kind === 'multipart') {
      if (restIsNode()) {
        const multipart = glMultipartBody(body.parts);
        headers['Content-Type'] = multipart.contentType;
        if (multipart.length !== undefined) headers['Content-Length'] = String(multipart.length);
        data = await restNodeReadable(glUploadProgress(multipart.stream, multipart.length, request.onSendProgress));
      } else {
        data = glFormDataMultipart(body.parts);
        browserProgress = true;
      }
    } else if (body?.kind === 'raw') {
      const upload = body.upload;
      if (upload.length !== undefined) headers['Content-Length'] = String(upload.length);
      if (restIsNode()) {
        data = await restNodeReadable(glUploadProgress(glUploadStream(upload.stream), upload.length, request.onSendProgress));
      } else if (typeof (upload.stream as Blob).arrayBuffer === 'function') {
        data = upload.stream;
        browserProgress = true;
      } else {
        throw new Error('GraphLink: axios cannot stream a request body in the browser; pass a Blob or File, or use the fetch adapter');
      }
    }
    const onSendProgress = request.onSendProgress;
    const response = await axiosInstance.request({
      method: request.method,
      url: restUrl(baseUrl, request),
      headers,
      data,
      responseType: 'arraybuffer',
      validateStatus: () => true,
      onUploadProgress: onSendProgress === undefined || !browserProgress
        ? undefined
        : (event) => onSendProgress(event.loaded, event.total ?? -1),
    });
    const responseHeaders: Record<string, string> = {};
    for (const [key, value] of Object.entries(response.headers)) {
      if (value !== undefined && value !== null) responseHeaders[key] = String(value);
    }
    return RestResponse.fromBytes(response.status, new Uint8Array(response.data), responseHeaders);
  };
}
''';
