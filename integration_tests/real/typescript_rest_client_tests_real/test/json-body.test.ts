import { beforeEach, describe, expect, it } from 'vitest';
import { Status, type GraphLinkClient } from '../lib/generated/graphlink';
import { bodyJson, header, newClient, resetServer } from './support';

let client: GraphLinkClient;

beforeEach(async () => {
  await resetServer();
  client = newClient();
});

describe('JSON body', () => {
  it('the argument itself is the whole body, unwrapped', async () => {
    const e = await client.mutations.eJson({ body: { name: 'Pen', price: 2.5, status: Status.Archived, tags: ['a', 'b'] } });
    expect(e.method).toBe('POST');
    expect(e.path).toBe('/echo/json');
    expect(e.contentType).toMatch(/^application\/json/);
    const json = bodyJson(e) as Record<string, unknown>;
    expect(json['name']).toBe('Pen');
    expect(json['price']).toBe(2.5);
    expect(json['status']).toBe('ARCHIVED');
    expect(json['tags']).toEqual(['a', 'b']);
    expect('body' in json).toBe(false);
  });

  it('a list argument is a JSON array', async () => {
    const e = await client.mutations.eJsonList({ body: [{ name: 'a' }, { name: 'b' }] });
    const json = bodyJson(e) as Array<Record<string, unknown>>;
    expect(json.map((j) => j['name'])).toEqual(['a', 'b']);
  });

  it('an empty list is still a body: []', async () => {
    const e = await client.mutations.eJsonList({ body: [] });
    expect(bodyJson(e)).toEqual([]);
  });

  it('a null optional body means no body and no Content-Type', async () => {
    const e = await client.mutations.eJsonOptional({});
    expect(e.bodySize).toBe(0);
    expect(e.contentType).toBeNull();
  });

  it('a present optional body is sent', async () => {
    const e = await client.mutations.eJsonOptional({ body: { name: 'x' } });
    expect((bodyJson(e) as Record<string, unknown>)['name']).toBe('x');
  });

  it('contentType on the operation replaces the default', async () => {
    const e = await client.mutations.eJsonType({ body: { name: 'x' } });
    expect(e.contentType).toMatch(/^application\/vnd\.test\+json/);
  });

  it('non-ASCII text round-trips as UTF-8', async () => {
    const name = 'é漢😀 "quoted" \\ back\nline';
    const e = await client.mutations.eJson({ body: { name } });
    expect((bodyJson(e) as Record<string, unknown>)['name']).toBe(name);
    expect(e.bodySize).toBe(new TextEncoder().encode(e.bodyText!).length);
  });

  it('a large JSON body is delivered intact', async () => {
    const tags = Array.from({ length: 20000 }, (_, i) => `tag-${i}`);
    const e = await client.mutations.eJson({ body: { name: 'big', tags } });
    expect(((bodyJson(e) as Record<string, unknown>)['tags'] as unknown[]).length).toBe(20000);
  });

  it('POST/PUT/PATCH use their declared methods and path variables', async () => {
    expect((await client.mutations.eJson({ body: { name: 'x' } })).method).toBe('POST');
    const put = await client.mutations.ePut({ id: 'a b', body: { name: 'x' } });
    expect([put.method, put.path]).toEqual(['PUT', '/echo/put/a%20b']);
    const patch = await client.mutations.ePatch({ id: 'p', body: { name: 'x' } });
    expect([patch.method, patch.path]).toEqual(['PATCH', '/echo/patch/p']);
  });

  it('path, header and body roles combine in one request', async () => {
    const e = await client.mutations.eHeaderBody({ id: 'i1', tenant: 'acme', body: { name: 'x' } });
    expect(e.path).toBe('/echo/hb/i1');
    expect(header(e, 'x-tenant')).toBe('acme');
    expect((bodyJson(e) as Record<string, unknown>)['name']).toBe('x');
  });
});
