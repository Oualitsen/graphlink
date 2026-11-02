import { beforeEach, describe, expect, it } from 'vitest';
import { RestError, type GraphLinkClient } from '../lib/generated/graphlink';
import { newClient, resetServer } from './support';

let client: GraphLinkClient;

beforeEach(async () => {
  await resetServer();
  client = newClient();
});

describe('transport edge cases', () => {
  it('a gzip-encoded response is decompressed before decoding', async () => {
    expect((await client.queries.gzipped()).map((p) => p.id)).toEqual(['p1', 'p2']);
  });

  it('a redirect is followed', async () => {
    expect(await client.queries.redirected()).toBe(7);
  });

  it('a large JSON response is decoded completely', async () => {
    const items = await client.queries.big({ n: 50000 });
    expect(items.length).toBe(50000);
    expect(items[items.length - 1].name).toBe('big-49999');
  });

  it('a 200 with invalid JSON is a format error, not a RestError', async () => {
    const failure = await client.queries.invalidJson().catch((e: unknown) => e);
    expect(failure).toBeInstanceOf(SyntaxError);
    expect(failure).not.toBeInstanceOf(RestError);
  });

  it('a non-JSON error body is kept as text on the RestError', async () => {
    const failure = await client.queries.htmlError().catch((e: unknown) => e);
    expect(failure).toBeInstanceOf(RestError);
    const error = failure as RestError;
    expect(error.status).toBe(500);
    expect(error.body).toContain('Internal Server Error');
    expect(error.headers['content-type']).toMatch(/^text\/html/);
  });
});
