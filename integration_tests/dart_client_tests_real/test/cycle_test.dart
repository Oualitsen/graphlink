import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'real_server_adapter.dart';

// The schema has User.posts: [Post!] and Post.author: User! — a cycle.
// The generator breaks it by expanding author's fields inline inside
// _all_fields_Post. Use "user-with-posts" to get a User with posts from server.

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('User.posts — cycle User → Post → User', () {
    test('User.posts is deserialized as a list', () async {
      final res = await client.queries.getUser(id: 'user-with-posts');
      expect(res.getUser.posts, isNotNull);
      expect(res.getUser.posts, isA<List>());
    });

    test('User.posts list has the correct length', () async {
      final res = await client.queries.getUser(id: 'user-with-posts');
      expect(res.getUser.posts!.length, equals(1));
    });

    test('User.posts[0] has correct scalar fields', () async {
      final res = await client.queries.getUser(id: 'user-with-posts');
      final post = res.getUser.posts!.first;
      expect(post.id, equals('post-10'));
      expect(post.title, equals('Cyclic Post'));
      expect(post.viewCount, equals(7));
    });

    test('User.posts[0].author is deserialized (cycle broken at one level)', () async {
      final res = await client.queries.getUser(id: 'user-with-posts');
      final author = res.getUser.posts!.first.author;
      expect(author.id, equals('user-1'));
      expect(author.name, equals('Alice Smith'));
    });

    test('User.posts[0].author.address is accessible', () async {
      final res = await client.queries.getUser(id: 'user-with-posts');
      final author = res.getUser.posts!.first.author;
      expect(author.address.city, equals('Springfield'));
    });

    test('User.posts is null for Alice (standard user-1)', () async {
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.posts, isNull);
    });
  });

  group('Post.author — cycle Post → User → Post', () {
    test('Post.author is a full User', () async {
      final res = await client.queries.getPost(id: 'post-10');
      expect(res.getPost.author.id, equals('user-1'));
      expect(res.getPost.author.name, equals('Alice Smith'));
    });

    test('Post.author scalar fields accessible (projected type)', () async {
      final res = await client.queries.getPost(id: 'post-10');
      expect(res.getPost.author.email, equals('alice@test.com'));
      expect(res.getPost.author.tags, equals(['admin']));
    });
  });
}
