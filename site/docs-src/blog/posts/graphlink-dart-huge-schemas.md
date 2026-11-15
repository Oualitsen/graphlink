---
date: 2026-11-15
slug: graphlink-dart-huge-schemas
categories:
  - Dart
  - Flutter
description: "Set autoGenerateQueries to false and GraphLink generates only the operations you declare. Useful for huge schemas like GitHub or Shopify."
id: D-11
demo_repo_path: "dart/d-01-quickstart"
docs_page: ""
---

# GraphQL Codegen for Huge Schemas in Dart: Turn Off Auto-Generated Queries

By default, GraphLink reads your schema and generates a method for every query, mutation and subscription in it. For a bookstore that is exactly what you want. For a schema like GitHub's, GitLab's or Shopify's, it means a lot of generated code for operations your app will never call.

This post shows the option that changes that: `autoGenerateQueries`. The video shows all of it, and the sections below follow the same order.

<!-- more -->

<iframe width="560" height="315" src="https://www.youtube.com/embed/MwoNFNJZHj4" title="GraphLink for Dart: huge schemas and autoGenerateQueries" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

<p><a href="https://youtu.be/MwoNFNJZHj4" target="_blank" rel="noopener">Watch on YouTube</a></p>

## The default

With the bookstore schema from the quickstart, the generated client has a method for each operation in the schema, for example fetching a book by ID and fetching the list of books. You never had to write a query for them. That is the default: `autoGenerateQueries` is `true`.

## Turn it off

In `config.json`, under the Dart client config, set it to `false`:

```json
{
  "schemaPaths": ["schema.graphql", "queries.graphql"],
  "mode": "client",
  "outputDir": "lib/generated",
  "clientConfig": {
    "dart": {
      "packageName": "bookstore_quickstart",
      "autoGenerateQueries": false
    }
  }
}
```

In the video I delete the `lib/generated` folder first, so nothing old is left, and run the generator again:

```bash
glink -c config.json
```

## What is left

Before, the client had the book-by-ID and books methods. Now the generated queries class only has what you declared yourself, in the `queries.graphql` file from the previous video (`getBooksWithoutAuthors`). Everything else is gone.

Two things to know from the video:

- The file does not have to be called `queries.graphql`. It can be any file with any extension, as long as it is listed in the config next to the schema.
- Set the option back to `true`, or remove it, run the generator again, and the other methods come back. Nothing is lost, it is only a choice about what to generate.

## Which one should you use

My rule of thumb, from the video:

- **Small schema:** keep the default. You don't have to declare every query, and in general you want to be able to get every field.
- **Huge schema:** turn it off and declare only the operations your app uses.

The GitHub, GitLab and Shopify schemas are in the `examples` folder of the GraphLink repo, if you want to try it on something big.

## What this video does not cover

I did not run a real GitHub schema in the video, and I did not cover the other options for huge schemas. This one is the on/off switch.

## Try it

- Code from the video: [graphlink-demos](https://github.com/Oualitsen/graphlink-demos)
- The project: [github.com/Oualitsen/graphlink](https://github.com/Oualitsen/graphlink). A star on GitHub is the easiest way to help.
- Docs: [graphlink.dev](https://graphlink.dev)
