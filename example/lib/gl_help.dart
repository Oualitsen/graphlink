const glHelp = '''
GraphLink — comprehensive Dart client example

This example demonstrates the full capabilities of a GraphLink-generated
Dart client:

  • Queries with automatic caching (@glCache)
  • Mutations with cache invalidation (@glCacheInvalidate)
  • Real-time subscriptions over WebSocket
  • File upload (multipart)
  • Custom projections — fetching only the fields you need
  • Compound queries — multiple root fields in one round-trip
  • staleIfOffline — returning expired cache when the network is down
  • Dio HTTP adapter with auth header injection

─── How to generate the client ────────────────────────────────────────────

1. Install the CLI:
     dart pub global activate graphlink

2. Run the generator (reads glink.yaml automatically):
     glink

   Or with an explicit path:
     glink -c glink.yaml

   Watch mode (regenerate on every schema save):
     glink -w

   Or with build_runner:
     dart run build_runner build

3. Run this file:
     dart run main.dart

─── Schema summary ────────────────────────────────────────────────────────

  Types:   User, Post, Comment
  Enums:   PostStatus (DRAFT | PUBLISHED | ARCHIVED)
  Scalars: Upload  →  GLUpload (file uploads)

  Queries:
    getUser(id)            cached 5 min, staleIfOffline
    listPosts(status?)     cached 1 min
    getPost(id)            cached 2 min
    getUserCard(id)        projection: id, username, avatarUrl only
    listPostPreviews(?)    projection: no body field
    getPostWithAuthor(…)   compound: post + author in one call

  Mutations:
    createUser(input)      invalidates "users" cache tag
    createPost(input)      invalidates "posts" cache tag
    addComment(input)      invalidates "posts" cache tag
    uploadAvatar(id, file) multipart upload, invalidates "users"
    deleteAllPosts()       invalidates ALL cache entries

  Subscriptions:
    commentAdded(postId)   fires whenever a comment is added to a post
    postPublished          fires whenever a post is published
''';
