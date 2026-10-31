import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

describe('getAllScalars — all nullables null (scalar-1)', () => {
  it('id', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-1' });
    expect(res.getAllScalars.id).toBe('scalar-1');
  });

  it('strVal', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-1' });
    expect(res.getAllScalars.strVal).toBe('hello world');
  });

  it('intVal', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-1' });
    expect(res.getAllScalars.intVal).toBe(42);
  });

  it('floatVal', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-1' });
    expect(res.getAllScalars.floatVal).toBeCloseTo(3.14);
  });

  it('boolVal', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-1' });
    expect(res.getAllScalars.boolVal).toBe(true);
  });

  it('nullableStr is null', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-1' });
    expect(res.getAllScalars.nullableStr).toBeNull();
  });

  it('nullableInt is null', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-1' });
    expect(res.getAllScalars.nullableInt).toBeNull();
  });

  it('nullableFloat is null', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-1' });
    expect(res.getAllScalars.nullableFloat).toBeNull();
  });

  it('nullableBool is null', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-1' });
    expect(res.getAllScalars.nullableBool).toBeNull();
  });

  it('nullableId is null', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-1' });
    expect(res.getAllScalars.nullableId).toBeNull();
  });
});

describe('getAllScalars — all nullables present (scalar-2)', () => {
  it('negative intVal', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-2' });
    expect(res.getAllScalars.intVal).toBe(-1);
  });

  it('negative floatVal', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-2' });
    expect(res.getAllScalars.floatVal).toBeCloseTo(-0.5);
  });

  it('boolVal false', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-2' });
    expect(res.getAllScalars.boolVal).toBe(false);
  });

  it('nullableStr present', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-2' });
    expect(res.getAllScalars.nullableStr).toBe('present');
  });

  it('nullableInt present', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-2' });
    expect(res.getAllScalars.nullableInt).toBe(99);
  });

  it('nullableFloat present', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-2' });
    expect(res.getAllScalars.nullableFloat).toBeCloseTo(2.718);
  });

  it('nullableBool false (present)', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-2' });
    expect(res.getAllScalars.nullableBool).toBe(false);
  });

  it('nullableId present', async () => {
    const res = await client.queries.getAllScalars({ id: 'scalar-2' });
    expect(res.getAllScalars.nullableId).toBe('nid-1');
  });
});
