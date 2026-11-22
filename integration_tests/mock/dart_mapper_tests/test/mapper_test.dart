import 'package:graphlink_mapper_tests/generated/graphlink.dart';
import 'package:graphlink_mapper_tests/persistence.dart';
import 'package:test/test.dart';

void main() {
  final entity = UserEntity(
    id: '1',
    fullName: 'Ada Lovelace',
    nick: null,
    addresses: [AddressEntity(street: 'Main'), AddressEntity(street: 'Side')],
    home: AddressEntity(street: 'Home'),
  );

  group('external source (UserEntityMapper)', () {
    test('copies fields, maps the list and the nested value', () {
      final user = UserEntityMapper.toUser(entity, defaultNick: 'anon');
      expect(user.id, '1');
      expect(user.fullName, 'Ada Lovelace');
      expect(user.addresses.map((a) => a.street), ['Main', 'Side']);
      expect(user.home?.street, 'Home');
    });

    test('a null nullable field takes the default, a present one wins', () {
      expect(UserEntityMapper.toUser(entity, defaultNick: 'anon').nick, 'anon');
      final withNick = UserEntity(id: '2', fullName: 'B', nick: 'bee', addresses: [], home: null);
      final user = UserEntityMapper.toUser(withNick, defaultNick: 'anon');
      expect(user.nick, 'bee');
      expect(user.home, isNull);
      expect(user.addresses, isEmpty);
    });
  });

  group('external target (UserMapper)', () {
    final user = UserEntityMapper.toUser(entity, defaultNick: 'anon');

    test('builds the external class with its nested values', () {
      final back = UserMapper.toUserEntity(user);
      expect(back.id, '1');
      expect(back.fullName, 'Ada Lovelace');
      expect(back.nick, 'anon');
      expect(back.addresses.map((a) => a.street), ['Main', 'Side']);
      expect(back.home?.street, 'Home');
    });

    test('a null nested value stays null', () {
      final noHome = UserEntityMapper.toUser(UserEntity(id: '3', fullName: 'C', addresses: [], home: null), defaultNick: 'n');
      expect(UserMapper.toUserEntity(noHome).home, isNull);
    });
  });

  group('mapperStyle class between generated types', () {
    test('renames a field for one target', () {
      final user = UserEntityMapper.toUser(entity, defaultNick: 'anon');
      final summary = UserMapper.toUserSummary(user);
      expect(summary.id, '1');
      expect(summary.name, 'Ada Lovelace');
    });

    test('the generated type has no inline to method', () {
      final user = UserEntityMapper.toUser(entity, defaultNick: 'anon');
      expect(() => (user as dynamic).toUserSummary, throwsNoSuchMethodError);
    });
  });
}
