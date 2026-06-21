import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'fixtures.dart';
import 'mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late GraphLinkClient client;

  setUp(() {
    adapter = MockAdapter();
    client = GraphLinkClient(adapter: adapter.call, wsAdapter: MockWebSocketAdapter());
  });

  // The schema has User.posts: [Post!] and Post.author: User! — a cycle.
  // The generator breaks it by expanding author's fields inline inside
  // _all_fields_Post rather than recursing back to ..._all_fields_User.

  group('User.posts — cycle User → Post → User', () {
    setUp(() => adapter.registerData('getUser', {'getUser': kUserWithPostsJson}));

    test('User.posts is deserialized as a list', () async {
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.posts, isNotNull);
      expect(res.getUser.posts, isA<List>());
    });

    test('User.posts list has the correct length', () async {
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.posts!.length, equals(1));
    });

    test('User.posts[0] has correct scalar fields', () async {
      final res = await client.queries.getUser(id: 'user-1');
      final post = res.getUser.posts!.first;
      expect(post.id, equals('post-10'));
      expect(post.title, equals('Cyclic Post'));
      expect(post.viewCount, equals(7));
    });

    test('User.posts[0].author is deserialized (cycle broken at one level)', () async {
      final res = await client.queries.getUser(id: 'user-1');
      final author = res.getUser.posts!.first.author;
      expect(author?.id, equals('user-1'));
      expect(author?.name, equals('Alice Smith'));
    });

    test('User.posts[0].author.address is accessible', () async {
      final res = await client.queries.getUser(id: 'user-1');
      final author = res.getUser.posts!.first.author;
      expect(author?.address.city, equals('Springfield'));
    });

    test('User.posts is null when server returns null', () async {
      adapter.registerData('getUser', {'getUser': kUserAliceJson});
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.posts, isNull);
    });
  });

  group('Post.author — cycle Post → User → Post', () {
    setUp(() => adapter.registerData('getPost', {'getPost': kPostWithAuthorCycleJson}));

    test('Post.author is a full User', () async {
      final res = await client.queries.getPost(id: 'post-10');
      expect(res.getPost.author?.id, equals('user-1'));
      expect(res.getPost.author?.name, equals('Alice Smith'));
    });

    test('Post.author is a projected type with scalar fields accessible', () async {
      final res = await client.queries.getPost(id: 'post-10');
      // _all_fields_Post expands author inline (not via ..._all_fields_User)
      // so the author is a projected type — scalars and address are present,
      // but 'posts' is not part of the projected type (cycle broken at compile time).
      expect(res.getPost.author?.email, equals('alice@test.com'));
      expect(res.getPost.author?.tags, equals(['admin']));
    });
  });

  group('listUsers with cyclic User.posts', () {
    test('list of users with posts deserializes correctly', () async {
      adapter.registerData('listUsers', {
        'listUsers': [kUserWithPostsJson],
      });
      final res = await client.queries.listUsers();
      expect(res.listUsers.length, equals(1));
      expect(res.listUsers.first.posts!.first.title, equals('Cyclic Post'));
    });
  });
}
