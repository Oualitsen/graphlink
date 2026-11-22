import { describe, expect, it } from 'vitest';
import type { AddressEntity, UserEntity } from '../lib/persistence';

export function describeMappers(target: string, mappers: { UserEntityMapper: any; UserMapper: any }) {
  const { UserEntityMapper, UserMapper } = mappers;

  const address = (street: string): AddressEntity => ({ street });

  const entity = (): UserEntity => ({
    id: '1',
    fullName: 'Ada Lovelace',
    nick: null,
    addresses: [address('Main'), address('Side')],
    home: address('Home'),
  });

  describe(`${target}: external source (UserEntityMapper)`, () => {
    it('copies fields, maps the list and the nested value', () => {
      const user = UserEntityMapper.toUser(entity(), 'anon');
      expect(user.id).toBe('1');
      expect(user.fullName).toBe('Ada Lovelace');
      expect(user.addresses.map((a: AddressEntity) => a.street)).toEqual(['Main', 'Side']);
      expect(user.home?.street).toBe('Home');
    });

    it('a null nullable field takes the default, a present one wins', () => {
      expect(UserEntityMapper.toUser(entity(), 'anon').nick).toBe('anon');
      const other: UserEntity = { id: '2', fullName: 'B', nick: 'bee', addresses: [], home: null };
      const user = UserEntityMapper.toUser(other, 'anon');
      expect(user.nick).toBe('bee');
      expect(user.home ?? null).toBeNull();
      expect(user.addresses).toEqual([]);
    });
  });

  describe(`${target}: external target (UserMapper)`, () => {
    it('builds the external shape with its nested values', () => {
      const back = UserMapper.toUserEntity(UserEntityMapper.toUser(entity(), 'anon'));
      expect(back.id).toBe('1');
      expect(back.fullName).toBe('Ada Lovelace');
      expect(back.nick).toBe('anon');
      expect(back.addresses.map((a: AddressEntity) => a.street)).toEqual(['Main', 'Side']);
      expect(back.home?.street).toBe('Home');
    });

    it('a null nested value stays null', () => {
      const bare: UserEntity = { id: '3', fullName: 'C', nick: null, addresses: [], home: null };
      expect(UserMapper.toUserEntity(UserEntityMapper.toUser(bare, 'n')).home ?? null).toBeNull();
    });
  });

  describe(`${target}: mapperStyle class between generated types`, () => {
    it('renames a field for one target', () => {
      const summary = UserMapper.toUserSummary(UserEntityMapper.toUser(entity(), 'anon'));
      expect(summary.id).toBe('1');
      expect(summary.name).toBe('Ada Lovelace');
    });
  });
}
