import { beforeEach, describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { Literal } from '../lib/generated/graphlink.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

const fieldName: Record<string, string> = {
  type: 'type', default: 'default', in: 'in', is: 'is', var: 'var', val: 'val', fun: 'fun', new: 'new',
  import: 'import', return: 'return', object: 'object', from: 'from', None: 'none', True: 'true',
  func: 'func', range: 'range', self: 'self', Self: 'self2', init: 'init', Type: 'type2',
  Protocol: 'protocol', async: 'async', await: 'await', package: 'package', interface: 'interface',
  enum: 'enum', null: 'null',
};
const argName: Record<string, string> = {
  ...fieldName, default: 'default_', in: 'in_', var: 'var_', new: 'new_', import: 'import_',
  return: 'return_', True: 'true_', package: 'package_', interface: 'interface_', enum: 'enum_', null: 'null_',
};
const values = (names: Record<string, string>) =>
  Object.fromEntries(Object.entries(names).map(([wire, name]) => [name, `v:${wire}`]));

function expectEchoed(reserved: object) {
  const r = reserved as Record<string, string>;
  for (const [wire, name] of Object.entries(fieldName)) expect(r[name], wire).toBe(`v:${wire}`);
}

describe('reserved words', () => {
  it('as argument names', async () => {
    const r = (await client.queries.reservedEcho(values(argName) as never)).reservedEcho;
    expectEchoed(r);
  });

  it('as input fields and response fields', async () => {
    const r = (await client.queries.reservedEchoInput({ input: values(fieldName) as never })).reservedEchoInput;
    expectEchoed(r);
  });

  it('as operation names', async () => {
    expect((await client.queries.import({ value: 'a' })).import).toBe('a');
    expect((await client.queries.default({ value: 'b' })).default).toBe('b');
    expect((await client.queries.new({ value: 'c' })).new).toBe('c');
    expect((await client.queries.func({ value: 'd' })).func).toBe('d');
    expect((await client.queries.none({ value: 'e' })).none).toBe('e');
    expect((await client.queries.self({ value: 'f' })).self).toBe('f');
  });
});

describe('enum values that look like literals or keywords', () => {
  const all = [Literal.Default, Literal.Class, Literal.None, Literal.True, Literal.Nil, Literal.Undefined, Literal.NaN, Literal.Self];

  it('every value decodes', async () => {
    expect((await client.queries.literals()).literals).toEqual(all);
  });

  it('every value round trips as an argument', async () => {
    for (const v of all) expect((await client.queries.literalEcho({ v, all })).literalEcho).toBe(v);
  });
});

describe('type names that clash with the standard library', () => {
  it('all decode', async () => {
    const c = (await client.queries.clashes()).clashes;
    for (const name of ['error', 'response', 'request', 'list', 'map', 'object', 'optional', 'date', 'result', 'void'] as const) {
      expect(c[name].id, name).toBe(`${name}-1`);
    }
  });
});

describe('names that collide after normalisation or look odd', () => {
  it('every field round trips', async () => {
    const input = {
      userId2: 'user_id', userId: 'userId', urlValue: 'URLValue', httpServer: 'HTTPServer', leading: '_leading',
      trailing: 'trailing_', v2Name: 'v2_name', isActive: 'isActive', active: 'active', getX: 'getX', x: 'x',
    };
    expect((await client.queries.oddEcho({ input })).oddEcho).toEqual(input);
  });
});
