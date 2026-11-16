---
date: 2026-11-02
slug: graphlink-dart-custom-queries
categories:
  - Dart
  - Flutter
description: "Select only the fields you need in a GraphQL query and get a typed Dart method and a null-safe class with exactly those fields."
id: D-04
demo_repo_path: "dart/d-01-quickstart"
docs_page: ""
---

# Custom GraphQL Queries in Dart: Select Only the Fields You Need

GraphQL promises that you can ask for exactly what you want and no more. In the last video the generated client fetched every book together with its author. That is fine until you only need the books.

This post covers the next step: write your own query, let GraphLink generate the method for it, and see what the generated Dart looks like. The video shows all of it, and the sections below follow the same order.

<!-- more -->

<iframe width="560" height="315" src="https://www.youtube.com/embed/gHGtCBYaj7c" title="GraphLink for Dart: custom queries and typed projections" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

<p><a href="https://youtu.be/gHGtCBYaj7c" target="_blank" rel="noopener">Watch on YouTube</a></p>

## The query

The schema is still the bookstore from the quickstart: authors and books, where a `Book` has an `author`. We want the books without their authors. Create a second file next to the schema, `queries.graphql`:

```graphql
query getBooksWithoutAuthors {
  books {
    id
    title
    year
  }
}
```

The name is long on purpose. It comes from Java habits: it is verbose, but when you read it you know what you are going to get.

## Tell GraphLink about the file

If you run `glink` now, nothing new appears in the client. The generator only knows about the files listed in the config, so add the query file next to the schema:

```json
{
  "schemaPaths": ["schema.graphql", "queries.graphql"],
  "mode": "client",
  "outputDir": "lib/generated",
  "clientConfig": {
    "dart": {
      "packageName": "bookstore_quickstart"
    }
  }
}
```

I forgot this step in the video and had to debug it, so it is worth remembering. Run the command again:

```bash
glink -c config.json
```

## The generated method

The client now has a new method, next to the ones generated from the schema, with the same name as your query:

```dart
final response = await client.queries.getBooksWithoutAuthors();
print(response.books.first.title);
```

In the video this prints the first book's title, *The Dispossessed*. Everything is typed: there is no map and no cast.

## No dollar signs

Look at the generated names. There are no dollar signs in the functions or the types. Some GraphQL code generators add them, and I never understood why. GraphLink doesn't, because if your app already talks to a GraphQL server you shouldn't have to give up names like `Author` and `Book` for generated code. The names should be as natural as possible.

## A class for the projection

Open the response and you will find a new class named after the type and the fields you picked: `Book_IdTitleYear`. It has `id`, `title` and `year` as final fields, a constructor with named required parameters, and its own `toJson` and `fromJson`.

Why a new class and not the existing `Book`? Because `Book` has an `author`, and the schema says it is never null. If the query didn't select it and GraphLink reused `Book`, the only honest choice would be to make every field nullable, and you would be checking for null on values you know are there. With a dedicated class, a field that isn't null in the schema is still not null in your code. That is also why this works for languages with null safety: Dart, Kotlin and TypeScript (TypeScript handles it a bit differently).

## Try it

- Code from the video: [graphlink-demos](https://github.com/Oualitsen/graphlink-demos)
- The project: [github.com/Oualitsen/graphlink](https://github.com/Oualitsen/graphlink). A star on GitHub is the easiest way to help.
- Docs: [graphlink.dev](https://graphlink.dev)

The rest of the Dart series covers fragments, batching, caching and subscriptions.
