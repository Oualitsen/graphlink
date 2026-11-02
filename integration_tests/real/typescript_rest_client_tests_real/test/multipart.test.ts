import { beforeEach, describe, expect, it } from 'vitest';
import type { GraphLinkClient } from '../lib/generated/graphlink';
import { newClient, part, partsNamed, pattern, resetServer, sha256Of, uploadOf } from './support';
import { variant } from './variant';

let client: GraphLinkClient;

beforeEach(async () => {
  await resetServer();
  client = newClient();
});

describe('multipart body', () => {
  it('has a boundary and carries text parts without a filename', async () => {
    const e = await client.mutations.eMultipart({ title: 'Hello é' });
    expect(e.contentType).toMatch(/^multipart\/form-data; boundary=/);
    const title = part(e, 'title');
    expect(title.filename).toBeNull();
    expect(title.text).toBe('Hello é');
  });

  it('a file part keeps its bytes, filename and mime type', async () => {
    const bytes = pattern(70000);
    const e = await client.mutations.eMultipart({ one: uploadOf(bytes, { filename: 'photo.png', mimeType: 'image/png' }) });
    const p = part(e, 'one');
    expect(p.filename).toBe('photo.png');
    expect(p.contentType).toMatch(/^image\/png/);
    expect(p.size).toBe(bytes.length);
    expect(p.sha256).toBe(sha256Of(bytes));
  });

  it('a list of uploads repeats the part name, in order', async () => {
    const files = [pattern(10), pattern(2000), new Uint8Array(0)];
    const e = await client.mutations.eMultipart({ many: files.map((f, i) => uploadOf(f, { filename: `f${i}.bin` })) });
    const parts = partsNamed(e, 'many');
    expect(parts.map((p) => p.filename)).toEqual(['f0.bin', 'f1.bin', 'f2.bin']);
    expect(parts.map((p) => p.size)).toEqual([10, 2000, 0]);
    expect(parts.map((p) => p.sha256)).toEqual(files.map(sha256Of));
  });

  it('an upload of unknown length is buffered and still arrives intact', async () => {
    const bytes = pattern(300000);
    const e = await client.mutations.eMultipart({ one: uploadOf(bytes, { filename: 'u.bin', knownLength: false }) });
    expect(part(e, 'one').sha256).toBe(sha256Of(bytes));
  });

  it('a non-ASCII filename survives', async () => {
    const e = await client.mutations.eMultipart({ one: uploadOf(pattern(3), { filename: 'é漢.png' }) });
    expect([ 'é漢.png', encodeURIComponent('é漢.png')]).toContain(part(e, 'one').filename);
  });

  it('FLAT objects become text parts named with the configured separator', async () => {
    const e = await client.mutations.eMultipart({ meta: { name: 'm', tags: ['a', 'b'], address: { city: 'Oran' } } });
    expect(part(e, variant.key('meta', ['name'])).text).toBe('m');
    expect(partsNamed(e, variant.key('meta', ['tags'])).map((p) => p.text)).toEqual(variant.comma ? ['a,b'] : ['a', 'b']);
    expect(part(e, variant.key('meta', ['address', 'city'])).text).toBe('Oran');
  });

  it('JSON encoding is a part with an application/json content type', async () => {
    const e = await client.mutations.eMultipart({ asJson: { name: 'm' } });
    const p = part(e, 'j');
    expect(p.contentType).toMatch(/^application\/json/);
    expect((JSON.parse(p.text!) as Record<string, unknown>)['name']).toBe('m');
  });

  it('text, file and object parts travel together', async () => {
    const bytes = pattern(1000);
    const e = await client.mutations.eMultipart({
      title: 't',
      asJson: { name: 'm' },
      one: uploadOf(bytes, { filename: 'a.bin' }),
      many: [uploadOf(bytes, { filename: 'b.bin' }), uploadOf(bytes, { filename: 'c.bin' })],
    });
    expect(e.parts.map((p) => p.name)).toEqual(['title', 'j', 'one', 'many', 'many']);
  });

  it('when nothing is set there is no body and no Content-Type', async () => {
    const e = await client.mutations.eMultipart({});
    expect(e.bodySize).toBe(0);
    expect(e.contentType).toBeNull();
  });

  it('progress reports increasing byte counts ending at the total', async () => {
    const bytes = pattern(1500000);
    const reports: Array<[number, number]> = [];
    const e = await client.mutations.eMultipart(
      { one: uploadOf(bytes, { filename: 'big.bin' }) },
      (sent, total) => reports.push([sent, total]),
    );
    expect(part(e, 'one').sha256).toBe(sha256Of(bytes));
    expect(reports.length).toBeGreaterThan(0);
    for (let i = 1; i < reports.length; i++) {
      expect(reports[i][0]).toBeGreaterThanOrEqual(reports[i - 1][0]);
    }
    const last = reports[reports.length - 1];
    expect(last[0]).toBe(last[1]);
    expect(last[1]).toBeGreaterThan(bytes.length);
  });
});
