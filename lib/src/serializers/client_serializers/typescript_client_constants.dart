// TypeScript template strings emitted verbatim into the generated client file.

const tsUploadsFile = r'''
export type UploadProgressCallback = (sent: number, total: number) => void;

export type GLMultipartAdapter = (
  parts: Record<string, unknown>,
  onProgress?: UploadProgressCallback,
) => Promise<string>;

export interface GLUpload {
  stream: ReadableStream<Uint8Array> | Blob | File;
  length?: number;
  filename?: string;
  mimeType: string;
}

export function glUploadFromBlob(blob: Blob, filename?: string): GLUpload {
  return {
    stream: blob,
    length: blob.size,
    filename,
    mimeType: blob.type || 'application/octet-stream',
  };
}

export function glUploadFromFile(file: File): GLUpload {
  return {
    stream: file,
    length: file.size,
    filename: file.name,
    mimeType: file.type || 'application/octet-stream',
  };
}
''';

const tsCacheStore = r'''
export interface GraphLinkCacheStore {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  invalidate(key: string): Promise<void>;
  invalidateAll(): Promise<void>;
}

export class InMemoryGraphLinkCacheStore implements GraphLinkCacheStore {
  private readonly _store = new Map<string, string>();

  async get(key: string): Promise<string | null> {
    return this._store.get(key) ?? null;
  }

  async set(key: string, value: string): Promise<void> {
    this._store.set(key, value);
  }

  async invalidate(key: string): Promise<void> {
    this._store.delete(key);
  }

  async invalidateAll(): Promise<void> {
    this._store.clear();
  }
}
''';

const tsCacheInfra = r'''
const __GL_TAG_KEY_PREFIX__ = '__tag__';

class _GraphLinkCacheEntry {
  constructor(
    readonly data: string,
    readonly expiry: number,
    readonly stale = false,
  ) {}

  static fromJson(json: { data: string; expiry: number }): _GraphLinkCacheEntry {
    return new _GraphLinkCacheEntry(json.data, json.expiry);
  }

  toJson(): { data: string; expiry: number } {
    return { data: this.data, expiry: this.expiry };
  }

  get isExpired(): boolean {
    return Date.now() > this.expiry;
  }

  asStale(): _GraphLinkCacheEntry {
    return new _GraphLinkCacheEntry(this.data, this.expiry, true);
  }
}

class _GraphLinkTagEntry {
  readonly keys: Set<string>;

  constructor(keys: Set<string>) {
    this.keys = new Set(keys);
  }

  static fromJson(json: { keys: string[] }): _GraphLinkTagEntry {
    return new _GraphLinkTagEntry(new Set(json.keys));
  }

  toJson(): { keys: string[] } {
    return { keys: Array.from(this.keys) };
  }

  encode(): string { return JSON.stringify(this.toJson()); }

  static decode(raw: string): _GraphLinkTagEntry {
    return _GraphLinkTagEntry.fromJson(JSON.parse(raw));
  }

  add(key: string): void { this.keys.add(key); }
  remove(key: string): void { this.keys.delete(key); }
}

class _Lock {
  private _last: Promise<void> = Promise.resolve();

  synchronized<T>(fn: () => Promise<T>): Promise<T> {
    const next = this._last.then(() => fn());
    this._last = next.then(() => {}, () => {});
    return next;
  }
}

class _GraphLinkPartialQuery {
  readonly cacheKey: string | null;

  constructor(
    readonly query: string,
    readonly variables: Record<string, unknown>,
    readonly ttl: number,
    readonly tags: string[],
    readonly operationName: string,
    readonly elementKey: string,
    readonly fragmentNames: Set<string>,
    readonly argumentDeclarations: string[],
    readonly staleIfOffline: boolean,
  ) {
    this.cacheKey = ttl === 0
      ? null
      : _GraphLinkPartialQuery._computeCacheKey(operationName, variables);
  }

  private static _computeCacheKey(
    operationName: string,
    variables: Record<string, unknown>,
  ): string {
    const sorted = Object.fromEntries(
      Object.entries(variables).sort(([a], [b]) => a.localeCompare(b)),
    );
    const raw = `${operationName}:${JSON.stringify(sorted)}`;
    return _GraphLinkPartialQuery._fnv1a(raw);
  }

  private static _fnv1a(input: string): string {
    let hash = 0x811c9dc5;
    for (let i = 0; i < input.length; i++) {
      hash ^= input.charCodeAt(i);
      hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return hash.toString(16).padStart(8, '0');
  }
}
''';

const tsWsAdapter = r'''
export interface GraphLinkWsAdapter {
  connect(): Promise<void>;
  sendMessage(message: string): Promise<void>;
  get onMessageStream(): AsyncIterable<string>;
  close(): Promise<void>;
  connectionInitPayload(): Promise<Record<string, unknown> | null>;
  get onReconnect(): AsyncIterable<void>;
}
''';

const tsWsMessageTypes = r'''
const _GL_WS = {
  connectionInit: 'connection_init',
  connectionAck: 'connection_ack',
  ping: 'ping',
  pong: 'pong',
  subscribe: 'subscribe',
  next: 'next',
  error: 'error',
  complete: 'complete',
} as const;

type _GlWsMsg = { type: string; id?: string; payload?: unknown };
''';

const tsSubscriptionHandler = r'''
function _makeChannel<T>() {
  const queue: T[] = [];
  const errors: unknown[] = [];
  let resolver: (() => void) | null = null;
  let done = false;

  return {
    push(item: T): void {
      queue.push(item);
      resolver?.();
      resolver = null;
    },
    error(err: unknown): void {
      errors.push(err);
      resolver?.();
      resolver = null;
    },
    close(): void {
      done = true;
      resolver?.();
      resolver = null;
    },
    [Symbol.asyncIterator](): AsyncIterator<T> {
      return {
        async next(): Promise<IteratorResult<T>> {
          while (true) {
            if (errors.length > 0) throw errors.shift()!;
            if (queue.length > 0) return { value: queue.shift()!, done: false };
            if (done) return { value: undefined as unknown as T, done: true };
            await new Promise<void>(r => { resolver = r; });
          }
        },
      };
    },
  };
}

type _HandshakeStatus = 'none' | 'progress' | 'acknowledged';

class _SubscriptionHandler {
  private readonly _channels = new Map<string, ReturnType<typeof _makeChannel<Record<string, unknown>>>>();
  private readonly _payloads = new Map<string, GraphLinkPayload>();
  private _sinkPromise: Promise<{ send: (msg: string) => Promise<void> }> | null = null;
  private _handshakeStatus: _HandshakeStatus = 'none';
  private _handshakePromise: Promise<{ send: (msg: string) => Promise<void> }> | null = null;
  private readonly _pongMessage: string;
  // Broadcast fan-out: all listeners receive every incoming message, mirroring
  // Dart's broadcast stream contract on onMessageStream.
  private readonly _msgListeners = new Set<(msg: string) => void>();

  constructor(private readonly adapter: GraphLinkWsAdapter) {
    this._pongMessage = JSON.stringify({ type: _GL_WS.pong });
    // Single consumer — fans out to all registered listeners.
    this._msgListeners.add((msg) => this._dispatch(msg));
    (async () => {
      for await (const msg of adapter.onMessageStream) {
        for (const fn of this._msgListeners) fn(msg);
      }
    })();
    (async () => { for await (const _ of adapter.onReconnect) await this._onReconnect(); })();
  }

  private _initWs(): Promise<{ send: (msg: string) => Promise<void> }> {
    this._sinkPromise ??= this._connect();
    return this._sinkPromise;
  }

  private async _connect(): Promise<{ send: (msg: string) => Promise<void> }> {
    try {
      await this.adapter.connect();
      return this._handshakeStatus === 'acknowledged'
        ? { send: (m) => this.adapter.sendMessage(m) }
        : await this._doHandshake();
    } catch (e) {
      this._sinkPromise = null;
      throw e;
    }
  }

  private _doHandshake(): Promise<{ send: (msg: string) => Promise<void> }> {
    if (this._handshakePromise) return this._handshakePromise;
    this._handshakeStatus = 'progress';
    this._handshakePromise = this._performHandshake().then(
      sink => { this._handshakePromise = null; return sink; },
      err => { this._handshakePromise = null; throw err; },
    );
    return this._handshakePromise;
  }

  private async _performHandshake(): Promise<{ send: (msg: string) => Promise<void> }> {
    try {
      const payload = await this.adapter.connectionInitPayload();
      const initMsg: Record<string, unknown> = { type: _GL_WS.connectionInit };
      if (payload !== null) initMsg['payload'] = payload;
      await this.adapter.sendMessage(JSON.stringify(initMsg));

      // Register a temporary listener — runs alongside _dispatch on the same
      // fan-out set, so connection_ack is never stolen by the dispatch loop.
      await new Promise<void>((resolve, reject) => {
        const listener = (raw: string) => {
          const parsed: _GlWsMsg = JSON.parse(raw);
          if (parsed.type === _GL_WS.connectionAck) {
            this._msgListeners.delete(listener);
            resolve();
          } else if (parsed.type === _GL_WS.error) {
            this._msgListeners.delete(listener);
            reject(new Error('WebSocket handshake error'));
          }
        };
        this._msgListeners.add(listener);
      });

      this._handshakeStatus = 'acknowledged';
      return { send: (m) => this.adapter.sendMessage(m) };
    } catch (e) {
      this._handshakeStatus = 'none';
      throw e;
    }
  }

  private async _onReconnect(): Promise<void> {
    if (this._handshakeStatus === 'progress') return;
    this._handshakeStatus = 'none';
    if (this._payloads.size === 0) return;
    this._sinkPromise = null;
    try {
      const sink = await this._initWs();
      for (const [uuid, pl] of this._payloads) {
        await this._sendSubscribe(sink, uuid, pl);
      }
    } catch (e) {
      for (const ch of this._channels.values()) ch.error(e);
    }
  }

  private _dispatch(raw: string): void {
    const msg: _GlWsMsg = JSON.parse(raw);
    if (msg.type === _GL_WS.ping) {
      this.adapter.sendMessage(this._pongMessage);
      return;
    }
    const uuid = msg.id;
    if (!uuid) return;
    const ch = this._channels.get(uuid);
    if (!ch) return;

    switch (msg.type) {
      case _GL_WS.next:
        ch.push(((msg.payload as Record<string, unknown>)['data'] as Record<string, unknown>));
        break;
      case _GL_WS.complete:
        this._cleanup(uuid);
        break;
      case _GL_WS.error:
        ch.error(msg.payload);
        this._cleanup(uuid);
        break;
    }
  }

  private async _sendSubscribe(
    sink: { send: (msg: string) => Promise<void> },
    uuid: string,
    pl: GraphLinkPayload,
  ): Promise<void> {
    await sink.send(JSON.stringify({
      id: uuid,
      type: _GL_WS.subscribe,
      payload: { query: pl.query, operationName: pl.operationName, variables: pl.variables },
    }));
  }

  private _cleanup(uuid: string): void {
    this._channels.get(uuid)?.close();
    this._channels.delete(uuid);
    this._payloads.delete(uuid);
    if (this._channels.size === 0) this._sinkPromise = null;
  }

  private _generateUuid(): string {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
      const r = Math.random() * 16 | 0;
      return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
    });
  }

  async *handle(pl: GraphLinkPayload): AsyncGenerator<Record<string, unknown>> {
    const uuid = this._generateUuid();
    const ch = _makeChannel<Record<string, unknown>>();
    this._channels.set(uuid, ch);
    this._payloads.set(uuid, pl);

    let sink: { send: (msg: string) => Promise<void> } | null = null;
    try {
      sink = await this._initWs();
      await this._sendSubscribe(sink, uuid, pl);
    } catch (e) {
      this._cleanup(uuid);
      throw e;
    }

    try {
      for await (const item of ch) {
        yield item;
      }
    } finally {
      // If uuid is still in _channels the server has not sent complete yet —
      // this is a client-initiated cancel, so notify the server.
      // If uuid is gone, the server already sent complete; skip to avoid double cleanup.
      if (this._channels.has(uuid)) {
        void sink?.send(JSON.stringify({ id: uuid, type: _GL_WS.complete }));
        this._cleanup(uuid);
      }
    }
  }
}
''';

const tsFetchAdapter = r'''
// Minimal fetch-compatible function type — no DOM globals required.
type _FetchFn = (
  input: string,
  init?: Record<string, unknown>,
) => Promise<{ ok: boolean; status: number; statusText: string; text(): Promise<string> }>;

interface _FetchAdapterOptions {
  fetchFn?: _FetchFn;
  headers?: () => Record<string, string> | Promise<Record<string, string>>;
}

export function createFetchAdapter(
  url: string,
  options?: _FetchAdapterOptions,
): GraphLinkAdapter {
  return async (payload: string): Promise<string> => {
    const fn = (options?.fetchFn ?? (globalThis as Record<string, unknown>)['fetch']) as _FetchFn;
    const extraHeaders = options?.headers ? await options.headers() : {};
    const response = await fn(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...extraHeaders },
      body: payload,
    });
    if (!response.ok) {
      throw new Error(`GraphLink: HTTP ${response.status} ${response.statusText}`);
    }
    return response.text();
  };
}
''';

const tsMultipartFetchAdapter = r'''
export function createMultipartFetchAdapter(
  url: string,
  options?: _FetchAdapterOptions,
): GLMultipartAdapter {
  return async (parts: Record<string, unknown>, onProgress?: UploadProgressCallback): Promise<string> => {
    const fn = (options?.fetchFn ?? (globalThis as Record<string, unknown>)['fetch']) as _FetchFn;
    const extraHeaders = options?.headers ? await options.headers() : {};
    const formData = new FormData();
    for (const [key, value] of Object.entries(parts)) {
      if (value !== null && typeof value === 'object' && 'stream' in value) {
        const upload = value as GLUpload;
        formData.append(key, upload.stream as Blob, upload.filename);
      } else {
        formData.append(key, value as string);
      }
    }
    const response = await fn(url, { method: 'POST', body: formData, headers: extraHeaders });
    if (!response.ok) {
      throw new Error(`GraphLink: HTTP ${response.status} ${response.statusText}`);
    }
    return response.text();
  };
}
''';

const tsAxiosAdapter = r'''
// Minimal structural axios interface — no @types/axios required.
interface _AxiosLike {
  post(
    url: string,
    data?: unknown,
    config?: { headers?: Record<string, string>; responseType?: string },
  ): Promise<{ data: unknown }>;
}

interface _AxiosAdapterOptions {
  headers?: () => Record<string, string> | Promise<Record<string, string>>;
}

export function createAxiosAdapter(
  url: string,
  axiosInstance: _AxiosLike,
  options?: _AxiosAdapterOptions,
): GraphLinkAdapter {
  return async (payload: string): Promise<string> => {
    const extraHeaders = options?.headers ? await options.headers() : {};
    const response = await axiosInstance.post(url, payload, {
      headers: { 'Content-Type': 'application/json', ...extraHeaders },
      responseType: 'text',
    });
    return response.data as string;
  };
}
''';

const tsDefaultWsAdapter = r'''
export class DefaultGraphLinkWsAdapter implements GraphLinkWsAdapter {
  private _ws: WebSocket | null = null;
  private readonly _messageChannel = _makeChannel<string>();
  private readonly _reconnectChannel = _makeChannel<void>();
  private _connectPromise: Promise<void> | null = null;
  private _reconnectAttempts = 0;
  private _closed = false;
  private static readonly _MAX_RECONNECT = 10;

  constructor(
    private readonly url: string,
    private readonly headersProvider?: () => Promise<Record<string, string> | null>,
  ) {}

  async connect(): Promise<void> {
    this._connectPromise ??= this._doConnect();
    return this._connectPromise;
  }

  private async _doConnect(): Promise<void> {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(this.url, 'graphql-transport-ws');
      ws.onopen = () => { this._ws = ws; this._reconnectAttempts = 0; resolve(); };
      ws.onerror = (e) => reject(e);
      ws.onmessage = (e) => this._messageChannel.push(e.data as string);
      ws.onclose = () => this._scheduleReconnect();
    });
  }

  private _scheduleReconnect(): void {
    if (this._closed) return;
    if (this._reconnectAttempts >= DefaultGraphLinkWsAdapter._MAX_RECONNECT) return;
    const delay = Math.min(1000 * Math.pow(2, this._reconnectAttempts), 30_000);
    this._reconnectAttempts++;
    setTimeout(async () => {
      try {
        this._connectPromise = null;
        await this._doConnect();
        this._reconnectChannel.push();
      } catch { this._scheduleReconnect(); }
    }, delay);
  }

  async sendMessage(message: string): Promise<void> {
    this._ws?.send(message);
  }

  get onMessageStream(): AsyncIterable<string> {
    return this._messageChannel as unknown as AsyncIterable<string>;
  }

  get onReconnect(): AsyncIterable<void> {
    return this._reconnectChannel as unknown as AsyncIterable<void>;
  }

  async close(): Promise<void> {
    this._closed = true;
    this._ws?.close();
    this._ws = null;
  }

  async connectionInitPayload(): Promise<Record<string, unknown> | null> {
    return this.headersProvider?.() ?? null;
  }
}
''';
