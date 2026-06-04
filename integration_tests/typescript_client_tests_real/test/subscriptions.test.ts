import { describe, it, expect } from 'vitest';
import { GraphLinkClient, DefaultGraphLinkWsAdapter } from '../lib/generated/client/graph-link-client.js';
import type { UserCreatedResponse } from '../lib/generated/types/user-created-response.js';
import type { UserStatusChangedResponse } from '../lib/generated/types/user-status-changed-response.js';
import { realHttpAdapter, WS_URL } from './real-server-adapter.ts';

// Each test creates its own ws adapter and client — subscriptions are stateful.
function makeClient() {
  const wsAdapter = new DefaultGraphLinkWsAdapter(WS_URL);
  const client = new GraphLinkClient(realHttpAdapter, wsAdapter);
  return { client, wsAdapter };
}

// Collect n events from a callback-based subscription, with a timeout.
function collectEvents<T>(
  n: number,
  subscribe: (onData: (e: T) => void, onError: (e: unknown) => void) => () => void,
  timeoutMs = 8000,
): Promise<T[]> {
  return new Promise((resolve, reject) => {
    const events: T[] = [];
    const timer = setTimeout(() => reject(new Error(`timeout: got ${events.length}/${n} events`)), timeoutMs);
    subscribe(
      e => {
        events.push(e);
        if (events.length >= n) { clearTimeout(timer); resolve(events); }
      },
      err => { clearTimeout(timer); reject(err); },
    );
  });
}

// ── userCreated — basic event delivery ───────────────────────────────────────
// Spring streams Flux.just(ALICE, BOB) for userCreated.

describe('userCreated — single event', () => {
  it('first event is Alice (user-1)', async () => {
    const { client, wsAdapter } = makeClient();
    try {
      const events = await collectEvents<UserCreatedResponse>(
        1,
        (onData, onErr) => client.subscriptions.userCreated(onData, onErr),
      );
      expect(events[0].userCreated.id).toBe('user-1');
      expect(events[0].userCreated.name).toBe('Alice Smith');
    } finally {
      await wsAdapter.close();
    }
  }, 10000);

  it('event has correctly deserialized nested address', async () => {
    const { client, wsAdapter } = makeClient();
    try {
      const events = await collectEvents<UserCreatedResponse>(
        1,
        (onData, onErr) => client.subscriptions.userCreated(onData, onErr),
      );
      expect(events[0].userCreated.address.city).toBe('Springfield');
    } finally {
      await wsAdapter.close();
    }
  }, 10000);

  it('event has correctly deserialized enum status', async () => {
    const { client, wsAdapter } = makeClient();
    try {
      const events = await collectEvents<UserCreatedResponse>(
        1,
        (onData, onErr) => client.subscriptions.userCreated(onData, onErr),
      );
      expect(events[0].userCreated.status).toBe('ACTIVE');
    } finally {
      await wsAdapter.close();
    }
  }, 10000);
});

describe('userCreated — multiple events', () => {
  it('delivers Alice then Bob', async () => {
    const { client, wsAdapter } = makeClient();
    try {
      const events = await collectEvents<UserCreatedResponse>(
        2,
        (onData, onErr) => client.subscriptions.userCreated(onData, onErr),
      );
      expect(events).toHaveLength(2);
      expect(events[0].userCreated.id).toBe('user-1');
      expect(events[1].userCreated.id).toBe('user-2');
    } finally {
      await wsAdapter.close();
    }
  }, 10000);
});

describe('userCreated — unsubscribe', () => {
  it('calling unsub does not throw', async () => {
    const { client, wsAdapter } = makeClient();
    try {
      await collectEvents<UserCreatedResponse>(
        1,
        (onData, onErr) => {
          const unsub = client.subscriptions.userCreated(
            e => { onData(e); expect(() => unsub()).not.toThrow(); },
            onErr,
          );
          return unsub;
        },
      );
    } finally {
      await wsAdapter.close();
    }
  }, 10000);
});

// ── userStatusChanged — subscription with argument ───────────────────────────
// Spring streams Flux.just(userById(userId)) for userStatusChanged.

describe('userStatusChanged — subscription with argument', () => {
  it('delivers Alice for user-1', async () => {
    const { client, wsAdapter } = makeClient();
    try {
      const events = await collectEvents<UserStatusChangedResponse>(
        1,
        (onData, onErr) => client.subscriptions.userStatusChanged({ userId: 'user-1' }, onData, onErr),
      );
      expect(events[0].userStatusChanged.id).toBe('user-1');
    } finally {
      await wsAdapter.close();
    }
  }, 10000);

  it('delivers Bob for user-2', async () => {
    const { client, wsAdapter } = makeClient();
    try {
      const events = await collectEvents<UserStatusChangedResponse>(
        1,
        (onData, onErr) => client.subscriptions.userStatusChanged({ userId: 'user-2' }, onData, onErr),
      );
      expect(events[0].userStatusChanged.id).toBe('user-2');
    } finally {
      await wsAdapter.close();
    }
  }, 10000);
});
