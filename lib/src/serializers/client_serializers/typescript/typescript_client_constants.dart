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

// ── Cache store ───────────────────────────────────────────────────────────────

const tsCacheStore = r'''
export interface GraphLinkCacheStore {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  invalidate(key: string): Promise<void>;
  invalidateAll(): Promise<void>;
}
''';

const tsInMemoryCacheStore = r'''
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

// ── Cache infrastructure ──────────────────────────────────────────────────────

const tsCacheEntry = r'''
export class GraphLinkCacheEntry {
  constructor(
    readonly data: string,
    readonly expiry: number,
    readonly stale = false,
  ) {}

  static fromJson(json: { data: string; expiry: number }): GraphLinkCacheEntry {
    return new GraphLinkCacheEntry(json.data, json.expiry);
  }

  toJson(): { data: string; expiry: number } {
    return { data: this.data, expiry: this.expiry };
  }

  get isExpired(): boolean {
    return Date.now() > this.expiry;
  }

  asStale(): GraphLinkCacheEntry {
    return new GraphLinkCacheEntry(this.data, this.expiry, true);
  }
}
''';

const tsTagEntry = r'''
export const __GL_TAG_KEY_PREFIX__ = '__tag__';

export class GraphLinkTagEntry {
  readonly keys: Set<string>;

  constructor(keys: Set<string>) {
    this.keys = new Set(keys);
  }

  static fromJson(json: { keys: string[] }): GraphLinkTagEntry {
    return new GraphLinkTagEntry(new Set(json.keys));
  }

  toJson(): { keys: string[] } {
    return { keys: Array.from(this.keys) };
  }

  encode(): string { return JSON.stringify(this.toJson()); }

  static decode(raw: string): GraphLinkTagEntry {
    return GraphLinkTagEntry.fromJson(JSON.parse(raw));
  }

  add(key: string): void { this.keys.add(key); }
  remove(key: string): void { this.keys.delete(key); }
}
''';

const tsLock = r'''
export class GraphLinkLock {
  private _last: Promise<void> = Promise.resolve();

  synchronized<T>(fn: () => Promise<T>): Promise<T> {
    const next = this._last.then(() => fn());
    this._last = next.then(() => {}, () => {});
    return next;
  }
}
''';

const tsPartialQuery = r'''
export class GraphLinkPartialQuery {
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
      : GraphLinkPartialQuery._computeCacheKey(operationName, variables);
  }

  private static _computeCacheKey(
    operationName: string,
    variables: Record<string, unknown>,
  ): string {
    const sorted = Object.fromEntries(
      Object.entries(variables).sort(([a], [b]) => a.localeCompare(b)),
    );
    const raw = `${operationName}:${JSON.stringify(sorted)}`;
    return GraphLinkPartialQuery._fnv1a(raw);
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

// ── WebSocket infrastructure ───────────────────────────────────────────────────

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
export const _GL_WS = {
  connectionInit: 'connection_init',
  connectionAck: 'connection_ack',
  ping: 'ping',
  pong: 'pong',
  subscribe: 'subscribe',
  next: 'next',
  error: 'error',
  complete: 'complete',
} as const;

export type _GlWsMsg = { type: string; id?: string; payload?: unknown };
''';

const tsSubscriptionHandler = r'''
export function _makeChannel<T>() {
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

// Broadcast channel — each [Symbol.asyncIterator] call gets its own queue so
// all concurrent listeners receive every push (unlike _makeChannel which is
// single-consumer).
export function _makeBroadcastChannel<T>() {
  type _Sub = { q: T[]; res: (() => void) | null; done: boolean };
  const _subs: _Sub[] = [];
  let _closed = false;
  return {
    push(item: T): void {
      for (const s of _subs) { s.q.push(item); s.res?.(); s.res = null; }
    },
    close(): void {
      _closed = true;
      for (const s of _subs) { s.done = true; s.res?.(); s.res = null; }
    },
    [Symbol.asyncIterator](): AsyncIterator<T> {
      const s: _Sub = { q: [], res: null, done: _closed };
      _subs.push(s);
      return {
        async next(): Promise<IteratorResult<T>> {
          while (true) {
            if (s.q.length > 0) return { value: s.q.shift()!, done: false };
            if (s.done) return { value: undefined as unknown as T, done: true };
            await new Promise<void>(r => { s.res = r; });
          }
        },
        return(): Promise<IteratorResult<T>> {
          const i = _subs.indexOf(s);
          if (i !== -1) _subs.splice(i, 1);
          return Promise.resolve({ value: undefined as unknown as T, done: true });
        },
      };
    },
  };
}

type _HandshakeStatus = 'none' | 'progress' | 'acknowledged';

export class GraphLinkSubscriptionHandler {
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

    // Fire-and-forget: on failure keep _payloads alive so _onReconnect can
    // re-subscribe once the adapter comes back up (mirrors Dart behaviour).
    this._initWs().then(async (sink) => {
      await this._sendSubscribe(sink, uuid, pl);
    }).catch((_e) => {
      // Intentionally swallowed — subscription resumes on reconnect.
    });

    try {
      for await (const item of ch) {
        yield item;
      }
    } finally {
      // If uuid is still in _channels the server has not sent complete yet —
      // this is a client-initiated cancel, so notify the server.
      // If uuid is gone, the server already sent complete; skip to avoid double cleanup.
      if (this._channels.has(uuid)) {
        void this.adapter.sendMessage(
          JSON.stringify({ id: uuid, type: _GL_WS.complete })
        ).catch(() => {});
        this._cleanup(uuid);
      }
    }
  }
}
''';

String tsFetchAdapter(bool withParam) {
  final extraParam = withParam ? ', operationName: string' : '';
  final urlExpr = withParam ? "url + '?operationName=' + operationName" : 'url';
  return r'''
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
  return async (payload: string''' + extraParam + r'''): Promise<string> => {
    const fn = (options?.fetchFn ?? (globalThis as Record<string, unknown>)['fetch']) as _FetchFn;
    const extraHeaders = options?.headers ? await options.headers() : {};
    const response = await fn(''' + urlExpr + r''', {
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
}

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

String tsAxiosAdapter(bool withParam) {
  final extraParam = withParam ? ', operationName: string' : '';
  final urlExpr = withParam ? "url + '?operationName=' + operationName" : 'url';
  return r'''
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
  return async (payload: string''' + extraParam + r'''): Promise<string> => {
    const extraHeaders = options?.headers ? await options.headers() : {};
    const response = await axiosInstance.post(''' + urlExpr + r''', payload, {
      headers: { 'Content-Type': 'application/json', ...extraHeaders },
      responseType: 'text',
    });
    return response.data as string;
  };
}
''';
}

const tsDefaultWsAdapter = r'''
export class DefaultGraphLinkWsAdapter implements GraphLinkWsAdapter {
  private _ws: WebSocket | null = null;
  private readonly _messageChannel = _makeChannel<string>();
  private readonly _reconnectChannel = _makeBroadcastChannel<void>();
  private _connectPromise: Promise<void> | null = null;
  private _reconnectAttempts = 0;
  private _reconnecting = false;
  private _closed = false;

  constructor(
    private readonly url: string,
    private readonly headersProvider?: () => Promise<Record<string, string> | null>,
    private readonly maxReconnectAttempts: number | null = 10,
    private readonly maxReconnectDelay: number = 30_000,
    private readonly protocols: string | string[] = ['graphql-transport-ws'],
  ) {}

  get reconnectAttempts(): number { return this._reconnectAttempts; }

  async connect(): Promise<void> {
    this._connectPromise ??= this._doConnect();
    return this._connectPromise;
  }

  private async _doConnect(): Promise<void> {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(this.url, this.protocols);
      ws.onopen = () => { this._ws = ws; this._reconnectAttempts = 0; resolve(); };
      ws.onerror = (e) => { this._scheduleReconnect(); reject(e); };
      ws.onmessage = (e) => this._messageChannel.push(e.data as string);
      ws.onclose = () => this._scheduleReconnect();
    });
  }

  private _scheduleReconnect(): void {
    if (this._closed) return;
    if (this.maxReconnectAttempts !== null && this._reconnectAttempts >= this.maxReconnectAttempts) return;
    // Guard against duplicate timers from concurrent onerror + onclose events.
    if (this._reconnecting) return;
    this._reconnecting = true;
    const delay = Math.min(1000 * Math.pow(2, this._reconnectAttempts), this.maxReconnectDelay);
    this._reconnectAttempts++;
    setTimeout(async () => {
      this._reconnecting = false;
      if (this._closed) return;
      try {
        // Assign before awaiting so concurrent connect() calls reuse this promise.
        this._connectPromise = this._doConnect();
        await this._connectPromise;
        this._reconnectChannel.push();
      } catch {
        this._connectPromise = null;
        this._scheduleReconnect();
      }
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
    return (await this.headersProvider?.()) ?? null;
  }
}
''';

const tsSha256 = r'''
export class GraphLinkSha256 {
  private static readonly K: number[] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  private static rotr(x: number, n: number): number {
    return ((x >>> n) | (x << (32 - n))) >>> 0;
  }

  static hex(input: string): string {
    const data = new TextEncoder().encode(input);
    const bitLength = data.length * 8;
    const bytes = new Uint8Array(Math.ceil((data.length + 9) / 64) * 64);
    bytes.set(data);
    bytes[data.length] = 0x80;
    const end = bytes.length;
    const high = Math.floor(bitLength / 0x100000000);
    bytes[end - 8] = (high >>> 24) & 0xff;
    bytes[end - 7] = (high >>> 16) & 0xff;
    bytes[end - 6] = (high >>> 8) & 0xff;
    bytes[end - 5] = high & 0xff;
    bytes[end - 4] = (bitLength >>> 24) & 0xff;
    bytes[end - 3] = (bitLength >>> 16) & 0xff;
    bytes[end - 2] = (bitLength >>> 8) & 0xff;
    bytes[end - 1] = bitLength & 0xff;

    const state = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    const w = new Array<number>(64).fill(0);
    for (let offset = 0; offset < bytes.length; offset += 64) {
      for (let i = 0; i < 16; i++) {
        const j = offset + i * 4;
        w[i] = ((bytes[j] << 24) | (bytes[j + 1] << 16) | (bytes[j + 2] << 8) | bytes[j + 3]) >>> 0;
      }
      for (let i = 16; i < 64; i++) {
        const s0 = GraphLinkSha256.rotr(w[i - 15], 7) ^ GraphLinkSha256.rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        const s1 = GraphLinkSha256.rotr(w[i - 2], 17) ^ GraphLinkSha256.rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
      }
      let [a, b, c, d, e, f, g, h] = state;
      for (let i = 0; i < 64; i++) {
        const s1 = GraphLinkSha256.rotr(e, 6) ^ GraphLinkSha256.rotr(e, 11) ^ GraphLinkSha256.rotr(e, 25);
        const ch = (e & f) ^ (~e & g);
        const t1 = (h + s1 + ch + GraphLinkSha256.K[i] + w[i]) >>> 0;
        const s0 = GraphLinkSha256.rotr(a, 2) ^ GraphLinkSha256.rotr(a, 13) ^ GraphLinkSha256.rotr(a, 22);
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const t2 = (s0 + maj) >>> 0;
        h = g;
        g = f;
        f = e;
        e = (d + t1) >>> 0;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) >>> 0;
      }
      const working = [a, b, c, d, e, f, g, h];
      for (let i = 0; i < 8; i++) {
        state[i] = (state[i] + working[i]) >>> 0;
      }
    }
    return state.map((v) => v.toString(16).padStart(8, '0')).join('');
  }
}
''';
