import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { httpAdapterForPort, newWsAdapterForPort } from './real-server-adapter';

const FAULT_PORT = Number(process.env['WS_FAULT_PORT'] ?? 9943);
const FAULT_URL = `http://127.0.0.1:${FAULT_PORT}`;
const HUGE: { users: number } = JSON.parse(readFileSync(new URL('../../fault_server/huge_case.json', import.meta.url), 'utf8'));

const arm = () => fetch(`${FAULT_URL}/_arm?fault=huge-users`, { method: 'POST' });

describe('a response of about 10 MB', () => {
  it('is decoded without loss', async () => {
    await fetch(`${FAULT_URL}/_reset`, { method: 'POST' });
    await arm();
    const ws = newWsAdapterForPort(FAULT_PORT);
    const client = new GraphLinkClient(httpAdapterForPort(FAULT_PORT), ws);
    try {
      const started = Date.now();
      const response = await client.queries.fetchBigUsers({ count: HUGE.users });
      const elapsed = Date.now() - started;

      const users = response.bigUsers;
      expect(users.length).toBe(HUGE.users);
      expect(users[0]!.id).toBe('user-0');
      expect(users[HUGE.users - 1]!.name).toBe(`User ${HUGE.users - 1} Ünï 日本`);
      expect(users[HUGE.users - 1]!.email).toBe(`user-${HUGE.users - 1}@example.com`);
      expect(users[1]!.status).toBe('INACTIVE');
      expect(users[Math.floor(HUGE.users / 2)]!.tags).toEqual(['alpha', 'beta']);
      expect(users[0]!.address.zip ?? null).toBeNull();
      expect(elapsed).toBeLessThan(30_000);

      await arm();
      expect((await client.queries.fetchBigUsers({ count: HUGE.users })).bigUsers.length).toBe(HUGE.users);
    } finally {
      await ws.close();
    }
  }, 120_000);
});
