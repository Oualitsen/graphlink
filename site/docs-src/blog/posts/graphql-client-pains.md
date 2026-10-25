---
date: 2026-10-25
slug: graphql-client-pains
categories:
  - Overview
description: "Six pains of hand-written GraphQL clients and how generating a typed client from your schema removes them, with a video for each."
id: O-01
demo_repo_path: ""
docs_page: ""
---

# The Pains of GraphQL Clients, and How to Remove Them

GraphQL is a good deal on paper. You get a typed schema, one endpoint, and clients that ask for exactly the data they need. Then you write the client, and the typed schema stops at the network boundary.

This post walks through the six pains I kept running into when building GraphQL clients, and what happens to each of them when the client code is generated from the schema instead of written by hand. Each section links to a short video that shows it in action.

<!-- more -->

## The idea: your schema is the source of truth

GraphLink is a compiler. You write your GraphQL schema once. GraphLink reads it and generates a typed, null-safe client in your language: Dart, Java, Kotlin, TypeScript or Swift.

Two things it is worth being clear about up front:

- **It is a code generator, not a runtime library.** The output is plain code in your language. Delete GraphLink tomorrow and your code still compiles.
- **The schema is the only thing you maintain.** Change the schema, run the generator again, and the compiler tells you what broke.

<iframe width="560" height="315" src="https://www.youtube.com/embed/W3kYySbsz0k" title="GraphLink intro: the pains of GraphQL" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

<p><a href="https://youtu.be/W3kYySbsz0k" target="_blank" rel="noopener">Watch the introduction on YouTube</a></p>

Now the pains.

## Pain 1: Raw maps and no compiler help

With a plain HTTP client, a GraphQL response is JSON. You decode it into a `Map<String, dynamic>` and dig out the values yourself:

```dart
final response = await http.post(
  Uri.parse(graphqlUrl),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'query': '{ books { title year author { name } } }'}),
);

final data = jsonDecode(response.body) as Map<String, dynamic>;
for (final book in data['data']['books']) {
  print('${book['title']} (${book['year']}) by ${book['author']['name']}');
}
```

Dart's `dynamic` makes this look easy, which is part of the problem. Rename a field on the server and this still compiles. You find out when a user opens the screen. In Java or Kotlin you would also have to cast at every step, which is more code and the same risk.

With a client generated from the schema, the same call looks like this:

```dart
final client = GraphLinkClient.withHttp(url: graphqlUrl);
final response = await client.queries.books();

for (final book in response.books) {
  print('${book.title} (${book.year}) by ${book.author.name}');
}
```

`books` is a list of `Book`. `title` is a `String`, `year` is an `int`, and `book.author.name` autocompletes. No casts, no maps, no string keys. Nullability from the schema carries through, so a field declared non-null is non-null in your code.

<iframe width="560" height="315" src="https://www.youtube.com/embed/G2QVInjpA-A" title="GraphQL raw maps pain" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

<p><a href="https://youtu.be/G2QVInjpA-A" target="_blank" rel="noopener">Watch on YouTube</a></p>

## Pain 2: Subscriptions

Subscriptions are the part of GraphQL that most clients make you build yourself. By hand it goes like this:

1. Open a WebSocket to the server.
2. Send a `connection_init` payload, with a bearer token if you need authentication.
3. Send the subscription itself.
4. Decode every raw message and branch on its type: `connection_ack`, `ping` (and reply with `pong`), `next`, `error`, `complete`.
5. Handle dropped connections and server restarts, with backoff and a reconnect that re-sends the init and subscribe messages.

That is a small protocol implementation, and it has to be right every time.

GraphLink generates this boilerplate for each subscription in your schema. In Dart you call a method on the generated `subscriptions` object and get a `Stream` back, then listen to it like any other stream. TypeScript works the same way. Java supports both reactive and blocking styles, and in the blocking one you pass a listener interface.

<iframe width="560" height="315" src="https://www.youtube.com/embed/PuU7B25OJC8" title="GraphQL subscriptions pain" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

<p><a href="https://youtu.be/PuU7B25OJC8" target="_blank" rel="noopener">Watch on YouTube</a></p>

## Pain 3: Caching

Caching is meant to stop the client from asking the server for something it was just told. Doing it by hand has two traps:

- **Partial responses overwrite complete ones.** You fetch a book with its title and ISBN and cache it. Elsewhere in the app, another query fetches the same book with only the ISBN, and it replaces the fuller entry.
- **The logic is yours to test.** Cache keys, expiry, and invalidation after mutations all need tests, and mocks for those tests.

GraphLink moves caching into the schema, which stays the source of truth. You mark a query with `@glCache`, giving it a time to live and a set of tags. To clear entries before they expire, you mark a mutation with `@glCacheInvalidate` and the tags it should invalidate:

```graphql
type Query {
  books: [Book!]! @glCache(ttl: "5m", tags: ["books"])
}

type Mutation {
  addBook(input: AddBookInput!): Book! @glCacheInvalidate(tags: ["books"])
}
```

When `addBook` succeeds, the generated code evicts everything tagged `books`. The heavy lifting is generated. What you write is a couple of lines in the schema.

<iframe width="560" height="315" src="https://www.youtube.com/embed/2Ojjk259hcI" title="GraphQL caching pain" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

<p><a href="https://youtu.be/2Ojjk259hcI" target="_blank" rel="noopener">Watch on YouTube</a></p>

## Pain 4: Batching meets caching

Batching is a real GraphQL feature: ask for a book and an author in one query, in one HTTP request. The problem appears when you combine it with a cache. Most caches store the whole response as a single entry. Later, when you ask for only the book, the cache misses, even though the book is sitting right there inside the batched response.

GraphLink does not cache the whole response as one entry. It splits the response into separate entries. Here is the sequence from the video:

1. The app loads a book by ID. That is a miss, so the request goes to the server.
2. The app sends a batched request for the book and an author. The book comes from the cache, and only the author goes to the server.
3. A mutation adds a book, which evicts the book cache entries. The next batched request hits for the author and fetches only the book.

Each request sends only what the cache does not already have.

<iframe width="560" height="315" src="https://www.youtube.com/embed/fVzvVfBl0IU" title="GraphQL caching with batched queries" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

<p><a href="https://youtu.be/fVzvVfBl0IU" target="_blank" rel="noopener">Watch on YouTube</a></p>

## Pain 5: File uploads

A word of caution first: uploading files through GraphQL is not recommended in general. GraphQL is text-based, and a separate REST service for uploads is often the better design. But plenty of servers do accept uploads through GraphQL, so a client should handle it.

By hand, it means following the GraphQL multipart request convention. The variable that holds the file has to be `null` in the query payload. You add an `operations` part and a `map` part, both JSON, that describe which form field belongs to which variable. You read the file from the device, attach it, send the request, and then decode the response as raw data again.

In GraphLink you declare a custom scalar and mark it with `@glUpload`:

```graphql
scalar Upload @glUpload
```

Any mutation that uses that scalar gets the multipart transport, and the generated client method takes a generated `GLUpload` type. In Java, for example, you create one from a `File`, a byte array, or an `InputStream`. The multipart request is generated for you.

<iframe width="560" height="315" src="https://www.youtube.com/embed/u5Jbknx7R9g" title="GraphQL file upload pain" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

<p><a href="https://youtu.be/u5Jbknx7R9g" target="_blank" rel="noopener">Watch on YouTube</a></p>

## Pain 6: Error handling

In GraphQL, an HTTP 200 does not mean success. A response can carry a normal status code and still contain a non-empty `errors` list, such as `not authorized`. A hand-written client has to check the status code, check the `errors` list, and do it consistently on every call. That is boilerplate that spreads through the code base.

GraphLink gives you two modes:

- **Default:** if the response contains errors, the call throws a GraphLink exception that carries the list of errors. Either the call worked or it threw.
- **Capture mode:** you mark a query or mutation with `@glCaptureErrors`, and the call returns the result with `data` and `errors` side by side instead of throwing. You check `response.hasErrors` yourself.

Capture mode earns its place with batched queries and partial failures. Suppose you ask for the list of books and the list of authors in one query, and you are allowed to see the books but not the authors. The server returns `data` with the books and a null for the authors, plus an `errors` entry explaining the authors failure. With capture mode, you keep the books and still see the error, instead of losing everything to an exception.

<iframe width="560" height="315" src="https://www.youtube.com/embed/ySqkQ6ssSgk" title="GraphQL error handling pain" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

<p><a href="https://youtu.be/ySqkQ6ssSgk" target="_blank" rel="noopener">Watch on YouTube</a></p>

## Why I built it

I wanted to use GraphQL with a Flutter app. On the server side I liked how Spring Boot's GraphQL support handled data: I did not need to write a lot of DTOs. On the client side I found an existing generator and was happy at first. Two things got in the way. It returned streams where I expected futures, and it produced names with dollar signs that I did not like.

The bigger issue was how it talked to the backend. At the time it sent the whole schema's worth of definitions, including fragments that the query did not use. A Java GraphQL server rejects a query with unused fragments, so it failed against my backend. I am not naming the library. The authors did good work, and it may work well with other backends. It did not work with mine, and a Java server will refuse anything it considers unnecessary.

That is where one of GraphLink's design rules comes from: send the minimum the backend needs. GraphLink decides which query is sent to the server.

Two other design points follow from that:

- **Framework-agnostic transport.** You provide the function that sends the request. In Dart that is a function that takes a string and returns a `Future<String>`. That makes it easy to mock in tests, and you do not need to test the generated code itself.
- **Server scaffolding.** GraphLink can also generate server code (Spring Boot and Express/Apollo), where you implement a few interfaces and the rest is done.

<iframe width="560" height="315" src="https://www.youtube.com/embed/W9MwmBmtIeA" title="GraphLink recap" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

<p><a href="https://youtu.be/W9MwmBmtIeA" target="_blank" rel="noopener">Watch the recap on YouTube</a></p>

## Honest limits

- You still need a GraphQL server. GraphLink generates the client, and optional server scaffolding, not your business logic.
- Generated code is overwritten every time you run the generator. Keep your own code outside the generated folder.

## Recap

One schema, typed and null-safe clients. Subscriptions, caching, batching, uploads and error handling are generated, not hand-written. Because the output is plain code, you can leave whenever you want.

## Try it

- Full video playlist: https://youtube.com/playlist?list=PLQCBiENjF_uU
- YouTube channel: https://www.youtube.com/@Graphlinkdev
- Docs and quickstart: https://graphlink.dev
- GraphLink on GitHub: https://github.com/Oualitsen/graphlink (a star helps a lot)
- Code from the videos: https://github.com/Oualitsen/graphlink-demos
- Community on Reddit: https://www.reddit.com/r/graphlinkdotdev/
- Follow on X: https://x.com/graphlinkdev

If you hit a problem, open an issue on GitHub. Tell me which pain bites you the most, and I will cover it in the next video.
