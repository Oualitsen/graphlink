import { describe, it, expect } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import type { UserCreatedResponse } from '../lib/generated/types/user-created-response.js';
import type { UserStatusChangedResponse } from '../lib/generated/types/user-status-changed-response.js';
import type { UserCreatedsResponse } from '../lib/generated/types/user-createds-response.js';
import { realHttpAdapter, WS_URL } from './real-server-adapter.ts';
import { DefaultGraphLinkWsAdapter } from '../lib/generated/graphlink.ts';

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

// ── multipleSubscriptions — concurrent subscriptions on one connection ────────
// The _SubscriptionHandler multiplexes over a single WS connection using UUIDs.
// These tests verify that events are routed correctly when several subscriptions
// are live at the same time.

describe('multipleSubscriptions — two different subscriptions concurrently', () => {
  it('userCreated and userStatusChanged both deliver their first event', async () => {
    const { client, wsAdapter } = makeClient();
    try {
      // Start both subscriptions before awaiting either.
      const [userCreatedEvents, statusEvents] = await Promise.all([
        collectEvents<UserCreatedResponse>(
          1,
          (onData, onErr) => client.subscriptions.userCreated(onData, onErr),
        ),
        collectEvents<UserStatusChangedResponse>(
          1,
          (onData, onErr) => client.subscriptions.userStatusChanged({ userId: 'user-1' }, onData, onErr),
        ),
      ]);
      expect(userCreatedEvents[0].userCreated.id).toBe('user-1');
      expect(statusEvents[0].userStatusChanged.id).toBe('user-1');
    } finally {
      await wsAdapter.close();
    }
  }, 10000);
});

describe('multipleSubscriptions — same subscription type, different args', () => {
  it('userStatusChanged for user-1 and user-2 receive independent events', async () => {
    const { client, wsAdapter } = makeClient();
    try {
      const [user1Events, user2Events] = await Promise.all([
        collectEvents<UserStatusChangedResponse>(
          1,
          (onData, onErr) => client.subscriptions.userStatusChanged({ userId: 'user-1' }, onData, onErr),
        ),
        collectEvents<UserStatusChangedResponse>(
          1,
          (onData, onErr) => client.subscriptions.userStatusChanged({ userId: 'user-2' }, onData, onErr),
        ),
      ]);
      expect(user1Events[0].userStatusChanged.id).toBe('user-1');
      expect(user1Events[0].userStatusChanged.status).toBe('ACTIVE');
      expect(user2Events[0].userStatusChanged.id).toBe('user-2');
      expect(user2Events[0].userStatusChanged.status).toBe('INACTIVE');
    } finally {
      await wsAdapter.close();
    }
  }, 10000);
});

describe('multipleSubscriptions — three concurrent subscriptions', () => {
  it('all three deliver their first event independently', async () => {
    const { client, wsAdapter } = makeClient();
    try {
      const [e1, e2, e3] = await Promise.all([
        collectEvents<UserCreatedResponse>(
          1,
          (onData, onErr) => client.subscriptions.userCreated(onData, onErr),
        ),
        collectEvents<UserStatusChangedResponse>(
          1,
          (onData, onErr) => client.subscriptions.userStatusChanged({ userId: 'user-1' }, onData, onErr),
        ),
        collectEvents<UserStatusChangedResponse>(
          1,
          (onData, onErr) => client.subscriptions.userStatusChanged({ userId: 'user-2' }, onData, onErr),
        ),
      ]);
      expect(e1[0].userCreated.id).toBe('user-1');
      expect(e2[0].userStatusChanged.id).toBe('user-1');
      expect(e3[0].userStatusChanged.id).toBe('user-2');
    } finally {
      await wsAdapter.close();
    }
  }, 10000);
});

describe('multipleSubscriptions — cancel one subscription, other continues', () => {
  it('unsubscribing early from one does not disrupt the sibling subscription', async () => {
    const { client, wsAdapter } = makeClient();
    try {
      // Subscribe to userCreated (server emits Alice + Bob, then closes).
      const userCreatedPromise = collectEvents<UserCreatedResponse>(
        2,
        (onData, onErr) => client.subscriptions.userCreated(onData, onErr),
      );

      // Subscribe to userStatusChanged then immediately cancel it.
      const unsub = client.subscriptions.userStatusChanged({ userId: 'user-1' }, () => {}, () => {});
      unsub();

      // userCreated must still deliver both events despite the sibling being cancelled.
      const events = await userCreatedPromise;
      expect(events).toHaveLength(2);
      expect(events[0].userCreated.id).toBe('user-1');
      expect(events[1].userCreated.id).toBe('user-2');
    } finally {
      await wsAdapter.close();
    }
  }, 10000);
});

describe('multipleSubscriptions — two identical subscriptions (no args)', () => {
  it('userCreated registered twice each receives all events independently', async () => {
    const { client, wsAdapter } = makeClient();
    try {
      // Same operation + same variables — each call gets its own UUID and server-side stream.
      const [events1, events2] = await Promise.all([
        collectEvents<UserCreatedResponse>(
          2,
          (onData, onErr) => client.subscriptions.userCreated(onData, onErr),
        ),
        collectEvents<UserCreatedResponse>(
          2,
          (onData, onErr) => client.subscriptions.userCreated(onData, onErr),
        ),
      ]);
      expect(events1).toHaveLength(2);
      expect(events1[0].userCreated.id).toBe('user-1');
      expect(events1[1].userCreated.id).toBe('user-2');
      expect(events2).toHaveLength(2);
      expect(events2[0].userCreated.id).toBe('user-1');
      expect(events2[1].userCreated.id).toBe('user-2');
    } finally {
      await wsAdapter.close();
    }
  }, 10000);
});

describe('multipleSubscriptions — two identical subscriptions (with args)', () => {
  it('userStatusChanged for user-1 registered twice each receives the event independently', async () => {
    const { client, wsAdapter } = makeClient();
    try {
      const [events1, events2] = await Promise.all([
        collectEvents<UserStatusChangedResponse>(
          1,
          (onData, onErr) => client.subscriptions.userStatusChanged({ userId: 'user-1' }, onData, onErr),
        ),
        collectEvents<UserStatusChangedResponse>(
          1,
          (onData, onErr) => client.subscriptions.userStatusChanged({ userId: 'user-1' }, onData, onErr),
        ),
      ]);
      expect(events1[0].userStatusChanged.id).toBe('user-1');
      expect(events1[0].userStatusChanged.status).toBe('ACTIVE');
      expect(events2[0].userStatusChanged.id).toBe('user-1');
      expect(events2[0].userStatusChanged.status).toBe('ACTIVE');
    } finally {
      await wsAdapter.close();
    }
  }, 10000);
});

describe('multipleSubscriptions — userCreated and userCreateds concurrently', () => {
  it('single-object and list subscriptions run side-by-side with distinct typed payloads', async () => {
    const { client, wsAdapter } = makeClient();
    try {
      const [singleEvents, listEvents] = await Promise.all([
        collectEvents<UserCreatedResponse>(
          1,
          (onData, onErr) => client.subscriptions.userCreated(onData, onErr),
        ),
        collectEvents<UserCreatedsResponse>(
          1,
          (onData, onErr) => client.subscriptions.userCreateds({ ids: ['user-1', 'user-2'] }, onData, onErr),
        ),
      ]);
      expect(singleEvents[0].userCreated.id).toBe('user-1');
      expect(listEvents[0].userCreateds).not.toBeNull();
      expect(listEvents[0].userCreateds).toHaveLength(2);
      expect(listEvents[0].userCreateds![0].id).toBe('user-1');
      expect(listEvents[0].userCreateds![1].id).toBe('user-2');
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
