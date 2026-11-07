import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

describe('keyword `class` on the wire', () => {
  it('a keyword query and argument round-trip against the server', async () => {
    const res = await client.queries.class({ class_: 'abc' });
    expect(res.class.id).toBe('abc');
    expect(res.class.class).toBe('class-of-abc');
  });

  it('a keyword input field round-trips through a mutation', async () => {
    const res = await client.mutations.makeClass({ input: { class: 'hello' } });
    expect(res.makeClass.id).toBe('made');
    expect(res.makeClass.class).toBe('hello');
  });
});
