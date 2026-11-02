import { beforeEach, describe, expect, it } from 'vitest';
import { RestError, type Echo } from '../lib/generated/graphlink';
import { formValue, newClient, part, pattern, queryValue, resetServer, serverUrl, uploadOf } from './support';

beforeEach(resetServer);

describe('base URL', () => {
  it('a path prefix is kept in front of the operation path', async () => {
    const e = await newClient({ baseUrl: `${serverUrl}/api` }).queries.eScalars({ id: 'p' });
    expect(e.path).toBe('/api/echo/scalars/p');
  });

  it('a trailing slash does not double the separator', async () => {
    const e = await newClient({ baseUrl: `${serverUrl}/api/` }).queries.eScalars({ id: 'p' });
    expect(e.path).toBe('/api/echo/scalars/p');
  });

  it('a base URL without a path works', async () => {
    const e = await newClient({ baseUrl: `${serverUrl}/` }).queries.eScalars({ id: 'p' });
    expect(e.path).toBe('/echo/scalars/p');
  });
});

describe('transport errors', () => {
  it('an unreachable server is not a RestError', async () => {
    const c = newClient({ baseUrl: 'http://127.0.0.1:1' });
    const failure = await c.queries.eAccept().catch((e: unknown) => e);
    expect(failure).toBeInstanceOf(Error);
    expect(failure).not.toBeInstanceOf(RestError);
  });

  it('a client keeps working after a transport error', async () => {
    const c = newClient();
    const dead = newClient({ baseUrl: 'http://127.0.0.1:1' });
    await expect(dead.queries.eAccept()).rejects.toBeDefined();
    expect((await c.queries.eAccept()).method).toBe('GET');
  });
});

describe('adapter', () => {
  it('concurrent requests do not mix their data', async () => {
    const c = newClient();
    const results = await Promise.all(Array.from({ length: 60 }, (_, i) => c.queries.eScalars({ id: `id${i}`, i })));
    for (let i = 0; i < 60; i++) {
      expect(results[i].path).toBe(`/echo/scalars/id${i}`);
      expect(queryValue(results[i], 'i')).toBe(`${i}`);
    }
  });

  it('mixed request kinds in parallel', async () => {
    const c = newClient();
    const out = await Promise.all([
      c.queries.eAccept(),
      c.mutations.eJson({ body: { name: 'x' } }),
      c.mutations.eForm({ name: 'f' }),
      c.mutations.eMultipart({ title: 't' }),
      c.mutations.eRaw({ file: uploadOf(pattern(1000)) }),
      c.queries.blob({ size: 2000 }).then((d) => d.bytes()),
    ]);
    expect((out[0] as Echo).method).toBe('GET');
    expect((out[1] as Echo).contentType).toMatch(/^application\/json/);
    expect(formValue(out[2] as Echo, 'name')).toBe('f');
    expect(part(out[3] as Echo, 'title').text).toBe('t');
    expect((out[4] as Echo).bodySize).toBe(1000);
    expect((out[5] as Uint8Array).length).toBe(2000);
  });
});
