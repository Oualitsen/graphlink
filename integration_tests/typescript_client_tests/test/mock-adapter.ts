// Local copy of the interface — structurally compatible with the generated one.
export interface GraphLinkWsAdapter {
  connect(): Promise<void>;
  sendMessage(message: string): Promise<void>;
  get onMessageStream(): AsyncIterable<string>;
  close(): Promise<void>;
  connectionInitPayload(): Promise<Record<string, unknown> | null>;
  get onReconnect(): AsyncIterable<void>;
}

export interface MockCall {
  operationName: string | null;
  variables: Record<string, unknown>;
  rawPayload: string;
}

function makeQueue<T>() {
  const items: T[] = [];
  const pending: Array<(r: IteratorResult<T>) => void> = [];
  return {
    push(item: T) {
      const resolve = pending.shift();
      resolve ? resolve({ value: item, done: false }) : items.push(item);
    },
    get iterable(): AsyncIterable<T> {
      return {
        [Symbol.asyncIterator]() {
          return {
            next(): Promise<IteratorResult<T>> {
              if (items.length > 0) return Promise.resolve({ value: items.shift()!, done: false });
              return new Promise(r => pending.push(r));
            },
          };
        },
      };
    },
  };
}

export class MockAdapter {
  private readonly _responses = new Map<string, string>();
  private readonly _calls: MockCall[] = [];
  simulateFailure = false;

  register(operationName: string, jsonResponse: string): void {
    this._responses.set(operationName, jsonResponse);
  }

  registerData(operationName: string, data: Record<string, unknown>): void {
    this.register(operationName, JSON.stringify({ data }));
  }

  registerErrors(operationName: string, errors: unknown[]): void {
    this.register(operationName, JSON.stringify({ data: null, errors }));
  }

  get calls(): readonly MockCall[] { return this._calls; }
  get lastCall(): MockCall | null { return this._calls.at(-1) ?? null; }
  get callCount(): number { return this._calls.length; }

  reset(): void {
    this._calls.length = 0;
    this._responses.clear();
    this.simulateFailure = false;
  }

  readonly call = async (payload: string): Promise<string> => {
    if (this.simulateFailure) throw new Error('Simulated network failure');

    const decoded = JSON.parse(payload) as { query?: string; variables?: Record<string, unknown> };
    const opName = MockAdapter._extractOperationName(decoded.query ?? '');

    this._calls.push({ operationName: opName, variables: decoded.variables ?? {}, rawPayload: payload });

    const response = opName != null ? this._responses.get(opName) : undefined;
    if (response != null) return response;

    throw new Error(
      `MockAdapter: no response registered for "${opName ?? 'unknown'}".\n` +
      `Registered: [${[...this._responses.keys()].join(', ')}]\n` +
      `Payload: ${payload}`,
    );
  };

  private static _extractOperationName(query: string): string | null {
    return /(?:query|mutation|subscription)\s+(\w+)/.exec(query.trim())?.[1] ?? null;
  }
}

export class MockWsAdapter implements GraphLinkWsAdapter {
  private readonly _messages = makeQueue<string>();
  private readonly _reconnects = makeQueue<void>();
  private _subscriptionId: string | null = null;

  /**
   * Push a typed data payload as a graphql-ws `next` message.
   * Requires the subscription handshake to be complete first — call
   * `await wsAdapter.waitForSubscription()` before using this.
   */
  pushData(data: Record<string, unknown>): void {
    if (this._subscriptionId == null) throw new Error('MockWsAdapter: no active subscription id');
    this._messages.push(JSON.stringify({ type: 'next', id: this._subscriptionId, payload: { data } }));
  }

  /** Poll until the subscribe message has been received (handshake + subscribe done). */
  async waitForSubscription(timeoutMs = 1000): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (this._subscriptionId == null) {
      if (Date.now() > deadline) throw new Error('Timeout waiting for subscription handshake');
      await new Promise(r => setTimeout(r, 5));
    }
  }

  /** Inject a raw message as if it arrived from the server. */
  push(message: string): void { this._messages.push(message); }

  /** Simulate a reconnect event. */
  reconnect(): void { this._reconnects.push(undefined); }

  async connect(): Promise<void> {}

  async sendMessage(message: string): Promise<void> {
    const parsed = JSON.parse(message) as { type: string; id?: string };
    if (parsed.type === 'connection_init') {
      // Respond with connection_ack after current call stack unwinds so the
      // ack listener is registered before the message is dispatched.
      setTimeout(() => this._messages.push(JSON.stringify({ type: 'connection_ack' })), 0);
    } else if (parsed.type === 'subscribe') {
      this._subscriptionId = parsed.id ?? null;
    }
  }

  async close(): Promise<void> {}
  async connectionInitPayload(): Promise<Record<string, unknown> | null> { return null; }

  get onMessageStream(): AsyncIterable<string> { return this._messages.iterable; }
  get onReconnect(): AsyncIterable<void> { return this._reconnects.iterable; }
}
