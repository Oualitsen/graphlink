---
date: 2026-10-29
slug: graphlink-dart-quickstart
categories:
  - Dart
  - Flutter
description: "A typed, null-safe Dart GraphQL client from your schema with one command: 30 files in about 10 ms, no GraphLink dependency."
id: D-02
demo_repo_path: "dart/d-01-quickstart"
docs_page: ""
---

# Generate a Typed GraphQL Client for Dart in One Command

A GraphQL schema is fully typed. Then you write the Dart client by hand, and the types stop at the network boundary: `Map<String, dynamic>`, string keys, casts, and a query string you hope matches the server.

GraphLink skips that part. It reads your schema and writes the client for you, with models, inputs, queries and mutations, all typed and null-safe. This post is the quickstart: one schema, one command, and a first query against a real server. The video shows all of it, and the sections below follow the same order.

<!-- more -->

<iframe width="560" height="315" src="https://www.youtube.com/embed/78LYiuWLKIU" title="GraphLink for Dart: generate a typed GraphQL client" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

<p><a href="https://youtu.be/78LYiuWLKIU" target="_blank" rel="noopener">Watch on YouTube</a></p>

## The schema

The example is a small bookstore: authors and books, two queries and one mutation. It is deliberately simple.

```graphql
type Author {
  id: ID!
  name: String!
}

type Book {
  id: ID!
  title: String!
  year: Int!
  author: Author!
}

input AddBookInput {
  title: String!
  year: Int!
  authorId: ID!
}

type Query {
  book(id: ID!): Book
  books: [Book!]!
}

type Mutation {
  addBook(input: AddBookInput!): Book!
}
```

## One config file, one command

GraphLink needs a small config file that points at the schema and says where the output goes:

```json
{
  "schemaPaths": ["schema.graphql"],
  "mode": "client",
  "typeMappings": {
    "ID": "String",
    "String": "String",
    "Float": "double",
    "Int": "int",
    "Boolean": "bool"
  },
  "outputDir": "lib/generated",
  "clientConfig": {
    "dart": {
      "packageName": "bookstore_quickstart"
    }
  }
}
```

`packageName` has to match the `name` in your `pubspec.yaml`. Then you run the CLI:

```bash
glink -c config.json
```

In the video it reports 30 files generated in about 10 milliseconds. Installation instructions for `glink` are in the docs at [graphlink.dev](https://graphlink.dev).

## What you get

Under `lib/generated` there are a few folders (`client`, `enums`, `inputs`, `interfaces` and `types`) and one file, `graphlink.dart`, which is the only thing you import.

Take the input type from the schema. The generated Dart class has typed fields, a constructor with named parameters, and `toJson` and `fromJson`. That means you don't need `json_serializable`, and you can remove it from your dependencies.

It is null-safe because the schema is. If you make a field optional in the schema, for example `name` on `Author`, run `glink` again and the Dart field and the constructor parameter become optional too. The compiler then points at every place in your code that needs to change.

Look at `pubspec.yaml` and you will find only `http`. GraphLink is not a dependency. It is a code generator, so the output is plain Dart, and if you delete GraphLink tomorrow your code still compiles.

## The adapter and the first query

The generated client needs an adapter. An adapter is a function that takes the payload and returns a `Future<String>` with the server's response. That is the only way GraphLink talks to your server, so it doesn't care how the data travels. For HTTP, GraphLink generates one for you:

```dart
final client = GraphLinkClient(
  adapter: GraphLinkHttpAdapter(url: 'http://localhost:8080/graphql'),
);

final response = await client.queries.books();
for (final book in response.books) {
  print('${book.title} (${book.year}) by ${book.author.name}');
}
```

The query for `book(id: ID!)` has a required, named `id` parameter, and `book.title` and `book.author.name` are typed values, not map lookups. In the video the server is a small Spring Boot app, and fetching book 1 and then book 2 returns the right titles and IDs.

## No magic

The last part of the video opens the generated query. The client declares the query and a map of fragments, one "all fields" fragment per type, and sends only the fragments the query needs. For `Book` that means its own fields plus the fragment for `Author`. All of it is ordinary Dart that you can read.

## Try it

- Code from the video: [graphlink-demos](https://github.com/Oualitsen/graphlink-demos)
- The project: [github.com/Oualitsen/graphlink](https://github.com/Oualitsen/graphlink). A star on GitHub is the easiest way to help.
- Docs: [graphlink.dev](https://graphlink.dev)

The rest of the Dart series covers custom queries, fragments, batching, caching and subscriptions.
