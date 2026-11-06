import { beforeEach, describe, expect, it } from 'vitest';
import type { Cat, Dog, GraphLinkClient, Product } from '../lib/generated/graphlink';
import { newClient, resetServer } from './support';

let client: GraphLinkClient;

beforeEach(async () => {
  await resetServer();
  client = newClient();
});

const names = (values: ReadonlyArray<{ __typename: string } | null | undefined>) => values.map((v) => v?.__typename);

describe('nested', () => {
  it('interface and union fields inside an object', async () => {
    const kennel = await client.queries.kennel();
    expect(kennel.resident!.__typename).toBe('Dog');
    expect((kennel.resident as Dog).barks).toBe(true);
    expect(kennel.hit!.__typename).toBe('Product');
    expect((kennel.hit as Product).name).toBe('Pen');
  });

  it('lists of interfaces and unions inside an object', async () => {
    const kennel = await client.queries.kennel();
    expect(names(kennel.featured)).toEqual(['Dog', 'Cat']);
    expect((kennel.featured[1] as Cat).lives).toBe(9);
    expect(names(kennel.hits!)).toEqual(['Product', 'Owner']);
  });

  it('null elements in a list of interfaces', async () => {
    const mixed = (await client.queries.kennel()).mixed!;
    expect(mixed).toHaveLength(3);
    expect(names(mixed)).toEqual(['Dog', undefined, 'Cat']);
    expect(mixed[1] ?? null).toBeNull();
  });

  it('null polymorphic fields', async () => {
    const empty = (await client.queries.shelter()).kennels[1];
    expect(empty.resident ?? null).toBeNull();
    expect(empty.featured).toEqual([]);
    expect(empty.mixed ?? null).toBeNull();
    expect(empty.hit ?? null).toBeNull();
    expect(empty.hits ?? null).toBeNull();
  });

  it('two levels deep', async () => {
    const shelter = await client.queries.shelter();
    expect(shelter.kennels).toHaveLength(2);
    expect(shelter.kennels[0].resident!.__typename).toBe('Dog');
    expect((shelter.kennels[0].featured[1] as Cat).name).toBe('Tom');
  });
});

describe('results', () => {
  it('[Pet]! keeps null elements', async () => {
    const pets = await client.queries.petsNullable();
    expect(pets).toHaveLength(3);
    expect(names(pets)).toEqual(['Dog', undefined, 'Cat']);
    expect(pets[1] ?? null).toBeNull();
  });

  it('[Pet!] decodes a JSON null as null', async () => {
    expect((await client.queries.petsOptional()) ?? null).toBeNull();
  });

  it('through responsePath', async () => {
    expect(names(await client.queries.petsWrapped())).toEqual(['Dog', 'Cat']);
  });

  it('from a mutation', async () => {
    const pet = await client.mutations.adoptPet({ id: 'c9' });
    expect(pet.__typename).toBe('Cat');
    expect(pet.id).toBe('c9');
    expect(pet.name).toBe('Adopted');
  });

  it('from a cached operation', async () => {
    const first = await client.queries.cachedPet({ id: 'd7' });
    const second = await client.queries.cachedPet({ id: 'd7' });
    expect(first!.__typename).toBe('Dog');
    expect(first!.name).toBe('Rex1');
    expect(second!.name).toBe('Rex1');
    expect((await client.queries.cachedPet({ id: 'd8' }))!.name).toBe('Rex1');
  });
});

describe('payload problems', () => {
  it('discriminator key absent', async () => {
    await expect(client.queries.petNoKind()).rejects.toThrow(/Pet.*kind/);
  });

  it('discriminator null', async () => {
    await expect(client.queries.petNullKind()).rejects.toThrow(/Pet.*kind/);
  });

  it('unknown keys inside a member are ignored', async () => {
    const pet = await client.queries.petExtraKeys();
    expect(pet.__typename).toBe('Dog');
    expect(pet.name).toBe('Rex');
  });

  it('a member missing a required field names the field', async () => {
    await expect(client.queries.petMissingField()).rejects.toThrow(/barks/);
  });
});
