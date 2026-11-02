import { beforeEach, describe, expect, it } from 'vitest';
import { RestError, Status, type GraphLinkClient } from '../lib/generated/graphlink';
import { MockRest, bytesUpload, clientFor, q } from './mock-rest';

const product = { id: 'p1', name: 'Pen', price: 2.5, status: 'ACTIVE', tags: ['a', 'b'] };
const delay = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

let rest: MockRest;
let client: GraphLinkClient;

beforeEach(() => {
  rest = new MockRest();
  client = clientFor(rest);
});

describe('requests', () => {
  it('path variable is encoded and enum query value sent', async () => {
    rest.on('GET', '/products/a%20b', { json: product });
    const result = await client.queries.product({ id: 'a b', status: Status.Archived });
    expect(result!.name).toBe('Pen');
    expect(rest.last.method).toBe('GET');
    expect(q(rest.last)).toBe('status=ARCHIVED');
    expect(rest.last.headers['Accept']).toBe('application/json');
    expect(rest.last.body).toBeUndefined();
    expect('Content-Type' in rest.last.headers).toBe(false);
  });

  it('defaults are sent, lists repeat the key, input spreads, input header spreads', async () => {
    rest.on('GET', '/products', { json: [product] });
    await client.queries.products({
      filter: { tag: 'x', minPrice: 3 },
      ids: ['1', '2'],
      auth: { token: 't', requestId: 'r1' },
    });
    expect(q(rest.last)).toBe('tag=x&minPrice=3&page=1&ids=1&ids=2');
    expect(rest.last.headers['token']).toBe('t');
    expect(rest.last.headers['X-Request-Id']).toBe('r1');
  });

  it('null optional arguments are omitted', async () => {
    rest.on('GET', '/products', { json: [] });
    await client.queries.products({});
    expect(q(rest.last)).toBe('page=1');
  });

  it('FLAT objects in a list use indexed keys and lists of scalars repeat', async () => {
    rest.on('GET', '/products/search', { json: { data: { total: 1, items: [product] } } });
    const page = await client.queries.search({
      q: 'pen',
      groups: [{ name: 'g', ids: [1, 2] }, { name: 'h' }],
      tags: ['x', 'y'],
    });
    expect(q(rest.last)).toBe('q=pen&groups.0.name=g&groups.0.ids=1&groups.0.ids=2&groups.1.name=h&tags=x&tags=y');
    expect(page.total).toBe(1);
    expect(page.items[0].id).toBe('p1');
  });

  it('JSON body is the argument itself with Content-Type', async () => {
    rest.on('POST', '/products', { status: 201, json: product });
    const created = await client.mutations.createProduct({ input: { name: 'Pen', price: 2.5 } });
    expect(created.id).toBe('p1');
    expect(JSON.parse(rest.bodies[0])).toEqual({ name: 'Pen', price: 2.5 });
    expect(rest.last.headers['Content-Type']).toBe('application/json');
  });

  it('form body carries only non-null fields', async () => {
    rest.on('POST', '/products/p1/rename', { json: product });
    await client.mutations.rename({ id: 'p1', name: 'New' });
    const body = rest.last.body;
    expect(body?.kind).toBe('form');
    expect(body?.kind === 'form' ? body.fields.map(([k, v]) => `${k}=${v}`) : []).toEqual(['name=New']);
    expect(rest.last.headers['Content-Type']).toBe('application/x-www-form-urlencoded');
  });

  it('multipart carries text and file parts', async () => {
    rest.on('POST', '/products/p1/gallery', { json: product });
    await client.mutations.gallery({
      id: 'p1',
      title: 'T',
      files: [bytesUpload('1', { filename: 'a.png' }), bytesUpload('2', { filename: 'b.png' })],
    });
    const body = rest.last.body;
    expect(body?.kind).toBe('multipart');
    const parts = body?.kind === 'multipart' ? body.parts : [];
    expect(parts.map((p) => p.name)).toEqual(['title', 'files', 'files']);
    expect(parts[0].value).toBe('T');
    expect(parts[2].file!.filename).toBe('b.png');
    expect('Content-Type' in rest.last.headers).toBe(false);
  });

  it('raw body streams the upload with its mime type', async () => {
    rest.on('PUT', '/products/p1/avatar', { status: 204 });
    await client.mutations.avatar({ id: 'p1', file: bytesUpload('bytes', { mimeType: 'image/png' }) });
    expect(rest.bodies[0]).toBe('bytes');
    expect(rest.last.headers['Content-Type']).toBe('image/png');
  });
});

describe('responses', () => {
  it('Void accepts any 2xx and ignores the body', async () => {
    rest.on('DELETE', '/products/p1', { status: 200, text: 'whatever' });
    await client.mutations.deleteProduct({ id: 'p1' });
    expect(rest.last.method).toBe('DELETE');
  });

  it('nullable result with an empty body is null', async () => {
    rest.on('GET', '/products/p1', { status: 204 });
    expect(await client.queries.product({ id: 'p1' })).toBeNull();
  });

  it('non-null result with an empty body is a decode error', async () => {
    rest.on('GET', '/products/count', { status: 200 });
    await expect(client.queries.count()).rejects.toThrow(/Empty REST response/);
  });

  it('non-2xx raises RestError with status, headers and body', async () => {
    rest.on('GET', '/products/p1', { status: 404, text: 'nope', headers: { 'x-a': 'b' } });
    const failure = await client.queries.product({ id: 'p1' }).catch((e: unknown) => e);
    expect(failure).toBeInstanceOf(RestError);
    const error = failure as RestError;
    expect(error.status).toBe(404);
    expect(error.body).toBe('nope');
    expect(error.headers['x-a']).toBe('b');
  });

  it('TEXT response is returned verbatim', async () => {
    rest.on('GET', '/products/p1/note', { text: 'hello' });
    expect(await client.queries.note({ id: 'p1' })).toBe('hello');
  });

  it('scalar JSON result', async () => {
    rest.on('GET', '/products/count', { json: 7 });
    expect(await client.queries.count()).toBe(7);
  });
});

describe('cache', () => {
  it('a cached GET query hits the adapter once', async () => {
    rest.on('GET', '/products/cached/p1', { json: product });
    await client.queries.cached({ id: 'p1' });
    await client.queries.cached({ id: 'p1' });
    expect(rest.calls.length).toBe(1);
    rest.on('GET', '/products/cached/p2', { json: product });
    await client.queries.cached({ id: 'p2' });
    expect(rest.calls.length).toBe(2);
  });

  it('a REST mutation invalidates the tag after a 2xx', async () => {
    rest.on('GET', '/products/cached/p1', { json: product });
    rest.on('PUT', '/products/cached/p1', { json: product });
    await client.queries.cached({ id: 'p1' });
    await client.mutations.updateCached({ id: 'p1', input: { name: 'x' } });
    await client.queries.cached({ id: 'p1' });
    expect(rest.calls.filter((c) => c.method === 'GET').length).toBe(2);
  });

  it('a failed mutation does not invalidate', async () => {
    rest.on('GET', '/products/cached/p1', { json: product });
    rest.on('PUT', '/products/cached/p1', { status: 500, text: 'boom' });
    await client.queries.cached({ id: 'p1' });
    await expect(client.mutations.updateCached({ id: 'p1', input: { name: 'x' } })).rejects.toBeInstanceOf(RestError);
    await client.queries.cached({ id: 'p1' });
    expect(rest.calls.filter((c) => c.method === 'GET').length).toBe(1);
  });

  it('staleIfOffline serves stale data on a transport failure only', async () => {
    rest.on('GET', '/products/offline/p1', { json: product });
    await client.queries.cachedOffline({ id: 'p1' });
    await delay(1100);
    rest.failTransport = true;
    expect((await client.queries.cachedOffline({ id: 'p1' }))!.id).toBe('p1');
    rest.failTransport = false;
    rest.on('GET', '/products/offline/p1', { status: 500, text: 'down' });
    await expect(client.queries.cachedOffline({ id: 'p1' })).rejects.toBeInstanceOf(RestError);
  });
});

it('GraphQL and REST operations share one client', async () => {
  rest.on('GET', '/products/count', { json: 3 });
  expect((await client.queries.ping()).ping).toBe('pong');
  expect(await client.queries.count()).toBe(3);
});

describe('downloads', () => {
  it('stream, filename, content type and length come from the response', async () => {
    rest.on('GET', '/products/p1/export', {
      text: 'abcdef',
      headers: { 'Content-Type': 'text/csv', 'Content-Length': '6', 'Content-Disposition': 'attachment; filename="p 1.csv"' },
    });
    const received: number[] = [];
    const download = await client.queries.export({ id: 'p1' }, (r, t) => received.push(r * 100 + t));
    expect(download.filename).toBe('p 1.csv');
    expect(download.contentType).toBe('text/csv');
    expect(download.length).toBe(6);
    expect(rest.last.headers['Accept']).toBe('*/*');
    expect(new TextDecoder().decode(await download.bytes())).toBe('abcdef');
    expect(received[received.length - 1]).toBe(606);
  });

  it('an RFC 5987 filename* is decoded', async () => {
    rest.on('GET', '/products/p1/export', {
      text: 'x',
      headers: { 'Content-Disposition': "attachment; filename*=UTF-8''p%201%C3%A9.csv" },
    });
    expect((await client.queries.export({ id: 'p1' })).filename).toBe('p 1é.csv');
  });

  it('a nullable download is null on 204', async () => {
    rest.on('GET', '/products/p1/maybe', { status: 204 });
    expect(await client.queries.maybeExport({ id: 'p1' })).toBeNull();
  });

  it('a non-null download on 204 is a decode error', async () => {
    rest.on('GET', '/products/p1/export', { status: 204 });
    await expect(client.queries.export({ id: 'p1' })).rejects.toThrow(/Empty REST response/);
  });

  it('non-2xx still raises RestError', async () => {
    rest.on('GET', '/products/p1/export', { status: 500, text: 'x' });
    await expect(client.queries.export({ id: 'p1' })).rejects.toBeInstanceOf(RestError);
  });
});
