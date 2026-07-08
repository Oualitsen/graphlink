import { describe, test, expect } from 'vitest';
import { Priority } from '../src/generated/enums/priority.js';
import { newClient } from './fixtures.js';

describe('defaults', () => {
  const client = newClient();

  test('input-field defaults applied when omitted', async () => {
    const c = (await client.queries.resolveConfig({ input: {} })).resolveConfig;
    expect(c.pageSize).toBe(25);
    expect(c.ratio).toBe(1.5);
    expect(c.sort).toBe('asc');
    expect(c.verbose).toBe(false);
    expect(c.priority).toBe(Priority.Medium);
    expect(c.tags).toEqual(['default', 'seed']);
    expect(c.empties).toEqual([]);
    expect(c.note).toBeNull();
  });

  test('explicit values override defaults', async () => {
    const c = (await client.queries.resolveConfig({
      input: { pageSize: 5, sort: 'desc', priority: Priority.High, note: 'x' },
    })).resolveConfig;
    expect(c.pageSize).toBe(5);
    expect(c.sort).toBe('desc');
    expect(c.priority).toBe(Priority.High);
    expect(c.note).toBe('x');
  });

  test('nested object arg default merges with field defaults', async () => {
    const range = (await client.queries.resolveRange({})).resolveRange;
    expect(range.min).toBe(5); // arg default { min: 5 }
    expect(range.max).toBe(100); // RangeInput field default
  });

  test('argument-level scalar defaults', async () => {
    expect((await client.queries.greet({})).greet).toBe('Hi world!');
    expect((await client.queries.greet({ name: 'Bob', times: 2 })).greet).toBe('Hi Bob!Hi Bob!');
  });

  test('enum argument: passed value round-trips; omitted uses default HIGH', async () => {
    expect((await client.queries.echoPriority({ level: Priority.Low })).echoPriority).toBe(Priority.Low);
    expect((await client.queries.echoPriority({})).echoPriority).toBe(Priority.High);
  });
});
