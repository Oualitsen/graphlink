import { describe, it, expect } from 'vitest';
import { newClient } from './real-server-adapter.ts';

describe('GraphQL error details', () => {
  it('error carries message, path, locations and typed extensions', async () => {
    const res = await newClient().queries.getUserOrErrors({ id: 'missing' });
    const e = res.errors![0];
    expect(res.errors).toHaveLength(1);
    expect(e.message).toBe('User not found: missing');
    expect(e.path).toEqual(['getUserOrErrors']);
    expect(e.locations![0].line).toBe(1);
    expect(e.extensions!['code']).toBe('NOT_FOUND');
    expect(e.extensions!['retryable']).toBe(false);
    expect(e.extensions!['detail']).toEqual({ id: 'missing', attempts: 3 });
  });

  it('partial data: ok is returned, bad is null, error path is the alias', async () => {
    const res = await newClient().queries.partialAliased();
    expect(res.data!.ok.id).toBe('user-1');
    expect(res.data!.bad).toBeNull();
    expect(res.errors).toHaveLength(1);
    expect(res.errors![0].path).toEqual(['bad']);
  });
});
