import { describe, test, expect } from 'vitest';
import { Keyword } from '../src/generated/enums/keyword.js';
import { newClient } from './fixtures.js';

describe('keywords', () => {
  const client = newClient();

  test('reserved-word fields round-trip (both / dart-only / java-only)', async () => {
    const r = (await client.queries.reserved()).reserved;
    expect(r.class).toBe('cls');
    expect(r.return).toBe(42);
    expect(r.new).toBe(true);
    expect(r.default).toBe('def');
    expect(r.is).toBe('yes');
    expect(r.in).toBe('inside');
    expect(r.with).toBe('w');
    expect(r.int).toBe(7); // `int` shadows the dart:core type -> sanitized to int_
    expect(r.synchronized).toBe(false);
    expect(r.native).toBe('n');
    expect(r.kind).toBe(Keyword.Class);
    expect(r.nested.value).toBe('v');
    expect(r.secret.token).toBe('tok');
  });

  test('reserved operation name + reserved argument names', async () => {
    const res = await client.queries.switch({ class_: 'x', return_: 5 });
    expect(res.switch.class).toBe('x');
    expect(res.switch.return).toBe(5);
  });

  test('leading-underscore operation', async () => {
    const res = await client.queries.status();
    expect(res.status).toBe('ok');
  });

  test('colliding field names stay distinct', async () => {
    const c = (await client.queries.collide()).collide;
    expect([c.class, c.class2]).toEqual(expect.arrayContaining(['A', 'B']));
  });

  test('reserved-word input fields (mutation)', async () => {
    const res = await client.mutations.echoReserved({
      input: { class: 'X', return: 5, default: 'D', is: true, synchronized: 3 },
    });
    expect(res.echoReserved.class).toBe('X');
    expect(res.echoReserved.return).toBe(5);
    expect(res.echoReserved.default).toBe('D');
  });
});
