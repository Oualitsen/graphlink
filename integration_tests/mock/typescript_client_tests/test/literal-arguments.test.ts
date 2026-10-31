import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { MockAdapter, MockWsAdapter } from './mock-adapter.ts';
import { kUserAliceJson, kUserBobJson } from './fixtures.ts';

let adapter: MockAdapter;
let client: GraphLinkClient;

beforeEach(() => {
  adapter = new MockAdapter();
  client = new GraphLinkClient(adapter.call, new MockWsAdapter());
});

const sentQuery = (): string => JSON.parse(adapter.lastCall!.rawPayload).query;

describe('literal arguments', () => {
  it('a string literal is sent inline and needs no parameter', async () => {
    adapter.registerData('findFirstUser', { findUser: kUserAliceJson });
    const res = await client.queries.findFirstUser();
    expect(res.findUser?.name).toBe('Alice Smith');
    expect(adapter.lastCall!.variables).toEqual({});
    expect(sentQuery()).toContain('findUser(id: "user-1")');
  });

  it('an enum literal is sent inline', async () => {
    adapter.registerData('listActiveUsers', { listUsersByStatus: [kUserAliceJson] });
    const res = await client.queries.listActiveUsers();
    expect(res.listUsersByStatus).toHaveLength(1);
    expect(adapter.lastCall!.variables).toEqual({});
    expect(sentQuery()).toContain('listUsersByStatus(status: ACTIVE)');
  });

  it('several literals in one field are sent inline', async () => {
    adapter.registerData('searchAlice', { searchUsers: [kUserAliceJson] });
    await client.queries.searchAlice();
    expect(adapter.lastCall!.variables).toEqual({});
    expect(sentQuery()).toContain('searchUsers(name: "Alice",limit: 5)');
  });

  it('a literal and a variable can be mixed', async () => {
    adapter.registerData('searchWithFixedLimit', { searchUsers: [kUserBobJson] });
    await client.queries.searchWithFixedLimit({ name: 'Bob' });
    expect(adapter.lastCall!.variables).toEqual({ name: 'Bob' });
    expect(sentQuery()).toContain('searchUsers(name: $name,limit: 10)');
  });

  it('dollar signs inside a literal reach the server unchanged', async () => {
    adapter.registerData('searchPrice', { searchUsers: [] });
    await client.queries.searchPrice();
    expect(adapter.lastCall!.variables).toEqual({});
    expect(sentQuery()).toContain('name: "cost $5 or $6"');
  });
});
