import { describe, it, expect } from 'vitest';
import { ApqServer } from './apq-server.ts';
import { newClient } from './helpers.ts';

const client = newClient(new ApqServer());

describe('glHash', () => {
  it('hashes a query like a reference SHA-256', () => {
    expect(client.queries.glHash('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(client.queries.glHash('')).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });

  it('hashes a real GraphQL document', () => {
    expect(client.queries.glHash('query GetUser($id: ID!){getUser(id:$id){id name}}')).toBe(
      '76c03fc2e5cc623d71d65ac35823728a3fd45da3b453349dafa9b6fc1d1b7abc',
    );
  });

  it('is the same for repeated calls', () => {
    const first = client.queries.glHash('query A{a}');
    expect(client.queries.glHash('query A{a}')).toBe(first);
    expect(client.queries.glHash('query B{b}')).not.toBe(first);
  });

  it('is shared by queries and mutations through the base class', () => {
    expect(client.mutations.glHash('abc')).toBe(client.queries.glHash('abc'));
  });
});
