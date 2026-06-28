// See lib/gl_help.dart for the full example description (glHelp constant).
library;

// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:graphlink_example/gl_help.dart';

import 'package:graphlink_example/generated/client/graph_link_client.dart';
import 'package:graphlink_example/generated/client/graph_link_uploads.dart';
import 'package:graphlink_example/generated/enums/post_status.dart';
import 'package:graphlink_example/generated/inputs/add_comment_input.dart';
import 'package:graphlink_example/generated/inputs/create_post_input.dart';
import 'package:graphlink_example/generated/inputs/create_user_input.dart';

const _httpUrl = 'http://localhost:8080/graphql';
const _wsUrl   = 'ws://localhost:8080/graphql';

// ---------------------------------------------------------------------------
// Client setup
// ---------------------------------------------------------------------------

/// Builds the GraphLink client with a Dio adapter.
///
/// The Dio adapter gives you full Dio feature support: interceptors,
/// `BaseOptions`, certificate pinning, proxy settings, etc.
///
/// Here we inject a Bearer token on every request via a Dio interceptor.
GraphLinkClient buildClient({String? authToken}) {
  return GraphLinkClient.withHttp(
    url: _httpUrl,
    wsUrl: _wsUrl,
    // Provide headers lazily — called before each request.
    headersProvider: () async => authToken != null
        ? {'Authorization': 'Bearer $authToken'}
        : null,
  );
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

/// Fetches a user using the auto-generated query (all fields).
///
/// The result is cached for 5 minutes under the "users" tag.
/// If the network is unavailable, the last cached value is returned instead
/// of throwing (`staleIfOffline: true` in the schema).
Future<void> demoGetUser(GraphLinkClient client, String userId) async {
  print('\n── getUser (all fields, cached 5 min) ──');

  final res = await client.queries.getUser(id: userId);
  final user = res.getUser;

  if (user == null) {
    print('User $userId not found');
    return;
  }

  print('id:        ${user.id}');
  print('username:  ${user.username}');
  print('email:     ${user.email}');
  print('bio:       ${user.bio ?? "(none)"}');
  print('posts:     ${user.posts.length}');

  // Second call is served from the in-memory cache — no network round-trip.
  print('\n[re-fetch — should be served from cache]');
  final cached = await client.queries.getUser(id: userId);
  print('username (cached): ${cached.getUser?.username}');
}

/// Fetches only id, username, and avatarUrl — a minimal "user card" projection.
///
/// Defined as a named query in the schema:
///
/// ```graphql
/// query getUserCard($id: ID!) @glCache(ttl: 120, tags: ["users"]) {
///   getUser(id: $id) {
///     id
///     username
///     avatarUrl
///   }
/// }
/// ```
Future<void> demoGetUserCard(GraphLinkClient client, String userId) async {
  print('\n── getUserCard (projection: id, username, avatarUrl) ──');

  final res = await client.queries.getUserCard(id: userId);
  final card = res.getUser;

  print('id:        ${card?.id}');
  print('username:  ${card?.username}');
  print('avatarUrl: ${card?.avatarUrl ?? "(none)"}');
}

/// Lists posts, returning only preview fields (no body).
///
/// ```graphql
/// query listPostPreviews($status: PostStatus) {
///   listPosts(status: $status) {
///     id
///     title
///     status
///     tags
///     createdAt
///   }
/// }
/// ```
Future<void> demoListPostPreviews(GraphLinkClient client) async {
  print('\n── listPostPreviews (projection: no body field) ──');

  final res = await client.queries.listPostPreviews(
    status: PostStatus.PUBLISHED,
  );

  for (final post in res.listPosts) {
    print('[${post.status.name}] ${post.title}  tags: ${post.tags.join(", ")}');
  }
}

/// Fetches a post and its author in a single GraphQL round-trip.
///
/// ```graphql
/// query getPostWithAuthor($postId: ID!, $authorId: ID!)
///   @glCache(ttl: 120, tags: ["posts", "users"]) {
///   post: getPost(id: $postId) {
///     ... _all_fields
///   }
///   author: getUser(id: $authorId) {
///     id
///     username
///     avatarUrl
///   }
/// }
/// ```
Future<void> demoGetPostWithAuthor(
    GraphLinkClient client, String postId, String authorId) async {
  print('\n── getPostWithAuthor (compound query) ──');

  final res = await client.queries.getPostWithAuthor(
    postId: postId,
    authorId: authorId,
  );

  final post   = res.post;
  final author = res.author;

  if (post != null) {
    print('Post:   [${post.status.name}] ${post.title}');
    print('Tags:   ${post.tags.join(", ")}');
  }
  if (author != null) {
    print('Author: ${author.username}  (${author.avatarUrl ?? "no avatar"})');
  }
}

// ---------------------------------------------------------------------------
// Mutations
// ---------------------------------------------------------------------------

/// Creates a user and a published post, then adds a comment.
///
/// Each mutation carries a `@glCacheInvalidate` directive in the schema,
/// so the relevant cache tags are evicted automatically after success.
Future<(String, String)> demoMutations(GraphLinkClient client) async {
  print('\n── mutations ──');

  // Create user
  final userRes = await client.mutations.createUser(
    input: CreateUserInput(
      username: 'alice',
      email: 'alice@example.com',
      bio: 'GraphQL enthusiast',
    ),
  );
  final user = userRes.createUser;
  print('Created user: ${user.id}  (${user.username})');

  // Create post
  final postRes = await client.mutations.createPost(
    input: CreatePostInput(
      title: 'Getting started with GraphLink',
      body: 'GraphLink generates a fully typed client from your GraphQL schema...',
      tags: ['graphql', 'dart', 'codegen'],
    ),
  );
  final post = postRes.createPost;
  print('Created post: ${post.id}  "${post.title}"');

  // Add a comment — invalidates "posts" tag so listPosts is refreshed
  final commentRes = await client.mutations.addComment(
    input: AddCommentInput(
      postId: post.id,
      body: 'Great post, Alice!',
    ),
  );
  print('Added comment: ${commentRes.addComment.id}');

  return (user.id, post.id);
}

// ---------------------------------------------------------------------------
// File upload
// ---------------------------------------------------------------------------

/// Uploads an avatar image using the GraphQL multipart upload spec.
///
/// The schema declares:
/// ```graphql
/// uploadAvatar(userId: ID!, file: Upload!): User!
/// ```
///
/// On the Dart side, `Upload` maps to [GLUpload] — wrap any [File] or stream
/// in it and the generated Dio adapter handles the multipart encoding.
Future<void> demoUpload(GraphLinkClient client, String userId) async {
  print('\n── uploadAvatar (multipart file upload) ──');

  // Simulate a file — in a real app bytes come from a file picker or camera.
  final pngBytes = Uint8List.fromList([137, 80, 78, 71]); // minimal PNG header

  final upload = GLUpload.fromBytes(
    pngBytes,
    filename: 'avatar.png',
    mimeType: 'image/png',
  );

  final res = await client.mutations.uploadAvatar(
    userId: userId,
    file: upload,
  );

  print('Avatar URL: ${res.uploadAvatar.avatarUrl}');
}

// ---------------------------------------------------------------------------
// Subscriptions
// ---------------------------------------------------------------------------

/// Subscribes to new comments on a post and cancels after 3 events.
///
/// The generated client returns a [Stream<CommentAddedResponse>].
/// Subscriptions are backed by a WebSocket that auto-reconnects on disconnect.
Future<void> demoSubscription(GraphLinkClient client, String postId) async {
  print('\n── commentAdded subscription (cancels after 3 events) ──');

  var received = 0;

  final sub = client.subscriptions
      .commentAdded(postId: postId)
      .listen((event) {
    final comment = event.commentAdded;
    print('[comment] ${comment.id}: "${comment.body}"');
    received++;
  });

  // In a real app you'd await user action; here we just wait briefly.
  await Future.delayed(const Duration(seconds: 5));
  await sub.cancel();
  print('Subscription cancelled after $received event(s)');
}

/// Subscribes to post-published events — no arguments needed.
Future<void> demoPostPublishedSubscription(GraphLinkClient client) async {
  print('\n── postPublished subscription (cancels after 2 events) ──');

  var received = 0;

  final sub = client.subscriptions.postPublished().listen((event) {
    final post = event.postPublished;
    print('[published] "${post.title}"  id: ${post.id}');
    received++;
    if (received >= 2) {
      // Stream auto-closes if the subscription is cancelled upstream.
    }
  });

  await Future.delayed(const Duration(seconds: 5));
  await sub.cancel();
  print('Subscription cancelled');
}

// ---------------------------------------------------------------------------
// Cache invalidation — nuke everything
// ---------------------------------------------------------------------------

/// Deletes all posts and wipes the entire client-side cache in one shot.
///
/// The schema declares:
/// ```graphql
/// deleteAllPosts: Boolean! @glCacheInvalidate(all: true)
/// ```
Future<void> demoCacheWipe(GraphLinkClient client) async {
  print('\n── deleteAllPosts (invalidates all cache entries) ──');
  final res = await client.mutations.deleteAllPosts();
  print('deleted: ${res.deleteAllPosts}');
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    print(glHelp);
    exit(0);
  }

  // Build the client — swap in a real token for authenticated endpoints.
  final client = buildClient(authToken: 'my-jwt-token');

  // 1. Mutations — create data and show cache invalidation
  final ids = await demoMutations(client);
  final userId = ids.$1;
  final postId = ids.$2;

  // 2. Queries — full fetch, then projection variants
  await demoGetUser(client, userId);
  await demoGetUserCard(client, userId);
  await demoListPostPreviews(client);
  await demoGetPostWithAuthor(client, postId, userId);

  // 3. File upload
  await demoUpload(client, userId);

  // 4. Subscriptions — real-time events over WebSocket
  await demoSubscription(client, postId);
  await demoPostPublishedSubscription(client);

  // 5. Nuke everything
  await demoCacheWipe(client);

  print('\nDone.');
}
