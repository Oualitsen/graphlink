import { beforeEach, describe, expect, it } from 'vitest';
import type { GraphLinkClient } from '../lib/generated/graphlink';
import { formPairs, formValue, newClient, resetServer } from './support';
import { variant } from './variant';

let client: GraphLinkClient;

beforeEach(async () => {
  await resetServer();
  client = newClient();
});

describe('form body', () => {
  it('is application/x-www-form-urlencoded and carries scalars', async () => {
    const e = await client.mutations.eForm({ name: 'Pen', n: 3 });
    expect(e.method).toBe('POST');
    expect(e.contentType).toMatch(/^application\/x-www-form-urlencoded/);
    expect(formPairs(e)).toEqual(['name=Pen', 'n=3']);
  });

  it('values with reserved characters are encoded and decode back', async () => {
    const value = 'a&b=c d+e%f/é😀\n';
    const e = await client.mutations.eForm({ name: value });
    expect(formValue(e, 'name')).toBe(value);
  });

  it('lists repeat the key (or join with commas)', async () => {
    const e = await client.mutations.eForm({ name: 'n', tags: ['x', 'y z'] });
    expect(formPairs(e)).toEqual(['name=n', ...variant.list('tags', ['x', 'y z'])]);
  });

  it('FLAT nests objects with the configured separator', async () => {
    const e = await client.mutations.eForm({ name: 'n', meta: { name: 'm', address: { city: 'Oran' } } });
    expect(formPairs(e)).toEqual([
      'name=n',
      `${variant.key('meta', ['name'])}=m`,
      `${variant.key('meta', ['address', 'city'])}=Oran`,
    ]);
  });

  it('SPREAD puts the fields at the top level', async () => {
    const e = await client.mutations.eForm({ name: 'n', filter: { tag: 't', minPrice: 1 } });
    expect(formPairs(e)).toEqual(['name=n', 'tag=t', 'minPrice=1']);
  });

  it('JSON encoding sends one entry holding the JSON text', async () => {
    const e = await client.mutations.eForm({ name: 'n', asJson: { name: 'm' } });
    expect((JSON.parse(formValue(e, 'j')!) as Record<string, unknown>)['name']).toBe('m');
  });

  it('null fields are omitted', async () => {
    const e = await client.mutations.eForm({ name: 'n' });
    expect(formPairs(e)).toEqual(['name=n']);
  });

  it('when every field is null the request has no body and no Content-Type', async () => {
    const e = await client.mutations.eFormEmpty({});
    expect(e.bodySize).toBe(0);
    expect(e.contentType).toBeNull();
  });

  it('a single present field sends a body', async () => {
    const e = await client.mutations.eFormEmpty({ b: 0 });
    expect(formPairs(e)).toEqual(['b=0']);
  });
});
