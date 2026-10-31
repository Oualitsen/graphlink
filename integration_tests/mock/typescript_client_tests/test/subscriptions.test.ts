import { describe, it, expect } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import type { UserCreatedResponse } from '../lib/generated/types/user-created-response.js';
import type { UserStatusChangedResponse } from '../lib/generated/types/user-status-changed-response.js';
import { MockAdapter, MockWsAdapter } from './mock-adapter.ts';
import { kUserAliceJson, kUserBobJson } from './fixtures.ts';

// Each test gets its own client + wsAdapter — subscriptions are stateful.
function makeClient() {
  const wsAdapter = new MockWsAdapter();
  const client = new GraphLinkClient(new MockAdapter().call, wsAdapter);
  return { client, wsAdapter };
}

// Wait for events to be delivered through the async generator chain.
const tick = (ms = 20) => new Promise<void>(r => setTimeout(r, ms));

// ── userCreated — basic event delivery ───────────────────────────────────────

describe('userCreated — single event', () => {
  it('delivers a typed event', async () => {
    const { client, wsAdapter } = makeClient();
    const events: UserCreatedResponse[] = [];

    client.subscriptions.userCreated(e => events.push(e));

    await wsAdapter.waitForSubscription();
    wsAdapter.pushData({ userCreated: kUserAliceJson });
    await tick();

    expect(events).toHaveLength(1);
    expect(events[0].userCreated.name).toBe('Alice Smith');
    expect(events[0].userCreated.id).toBe('user-1');
  });

  it('event has correctly deserialized nested address', async () => {
    const { client, wsAdapter } = makeClient();
    const events: UserCreatedResponse[] = [];

    client.subscriptions.userCreated(e => events.push(e));

    await wsAdapter.waitForSubscription();
    wsAdapter.pushData({ userCreated: kUserAliceJson });
    await tick();

    expect(events[0].userCreated.address.city).toBe('Springfield');
  });

  it('event has correctly deserialized enum status', async () => {
    const { client, wsAdapter } = makeClient();
    const events: UserCreatedResponse[] = [];

    client.subscriptions.userCreated(e => events.push(e));

    await wsAdapter.waitForSubscription();
    wsAdapter.pushData({ userCreated: kUserAliceJson });
    await tick();

    expect(events[0].userCreated.status).toBe('ACTIVE');
  });
});

// ── userCreated — multiple events ─────────────────────────────────────────────

describe('userCreated — multiple events', () => {
  it('delivers events in order', async () => {
    const { client, wsAdapter } = makeClient();
    const events: UserCreatedResponse[] = [];

    client.subscriptions.userCreated(e => events.push(e));

    await wsAdapter.waitForSubscription();
    wsAdapter.pushData({ userCreated: kUserAliceJson });
    wsAdapter.pushData({ userCreated: kUserBobJson });
    await tick();

    expect(events).toHaveLength(2);
    expect(events[0].userCreated.id).toBe('user-1');
    expect(events[1].userCreated.id).toBe('user-2');
  });

  it('all events are delivered', async () => {
    const { client, wsAdapter } = makeClient();
    let count = 0;

    client.subscriptions.userCreated(() => { count++; });

    await wsAdapter.waitForSubscription();
    for (let i = 0; i < 5; i++) wsAdapter.pushData({ userCreated: kUserAliceJson });
    await tick();

    expect(count).toBe(5);
  });
});

// ── userCreated — unsubscribe ─────────────────────────────────────────────────

describe('userCreated — unsubscribe', () => {
  it('returns an unsubscribe function', async () => {
    const { client, wsAdapter } = makeClient();
    client.subscriptions.userCreated(() => {});
    await wsAdapter.waitForSubscription();
    // unsub is a plain function — calling it must not throw
    const unsub = client.subscriptions.userCreated(() => {});
    expect(() => unsub()).not.toThrow();
  });

  it('no further events delivered when no data pushed after unsubscribe', async () => {
    const { client, wsAdapter } = makeClient();
    const events: UserCreatedResponse[] = [];

    const unsub = client.subscriptions.userCreated(e => events.push(e));
    await wsAdapter.waitForSubscription();

    wsAdapter.pushData({ userCreated: kUserAliceJson });
    await tick();
    expect(events).toHaveLength(1);

    unsub();
    // Wait with no new pushes — count must remain 1
    await tick();
    expect(events).toHaveLength(1);
  });
});

// ── userStatusChanged — subscription with argument ───────────────────────────

describe('userStatusChanged — subscription with argument', () => {
  it('delivers a typed event', async () => {
    const { client, wsAdapter } = makeClient();
    const events: UserStatusChangedResponse[] = [];

    client.subscriptions.userStatusChanged(
      { userId: 'user-1' },
      e => events.push(e),
    );

    await wsAdapter.waitForSubscription();
    wsAdapter.pushData({ userStatusChanged: kUserBobJson });
    await tick();

    expect(events).toHaveLength(1);
    expect(events[0].userStatusChanged.id).toBe('user-2');
    expect(events[0].userStatusChanged.status).toBe('INACTIVE');
  });
});

// ── error delivery ────────────────────────────────────────────────────────────

describe('userCreated — error delivery', () => {
  it('calls onError when server sends an error message', async () => {
    const { client, wsAdapter } = makeClient();
    const errors: unknown[] = [];

    client.subscriptions.userCreated(
      () => {},
      err => errors.push(err),
    );

    await wsAdapter.waitForSubscription();
    // graphql-ws error message — terminates the subscription
    wsAdapter.push(JSON.stringify({
      type: 'error',
      id: (wsAdapter as unknown as { _subscriptionId: string })._subscriptionId,
      payload: [{ message: 'Unauthorized' }],
    }));
    await tick();

    expect(errors).toHaveLength(1);
  });
});
