import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

describe('literal arguments against the real server', () => {
  it('a string literal selects the right user', async () => {
    const res = await client.queries.findFirstUser();
    expect(res.findUser?.name).toBe('Alice Smith');
    expect(res.findUser?.email).toBe('alice@test.com');
  });

  it('an enum literal filters on the server', async () => {
    const res = await client.queries.listActiveUsers();
    expect(res.listUsersByStatus.map(u => u.id)).toEqual(['user-1']);
  });

  it('several literals in one field are applied', async () => {
    const res = await client.queries.searchAlice();
    expect(res.searchUsers.map(u => u.name)).toEqual(['Alice Smith']);
  });

  it('an inline limit is enforced while the other argument stays a variable', async () => {
    const res = await client.queries.searchWithFixedLimit({ name: 's' });
    expect(res.searchUsers).toHaveLength(1);
  });

  it('dollar signs inside a literal form a valid query', async () => {
    const res = await client.queries.searchPrice();
    expect(res.searchUsers).toHaveLength(0);
  });
});
