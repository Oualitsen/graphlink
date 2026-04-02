# I Was Drowning in GraphQL Boilerplate in Flutter. Then I Found GraphLink. (Part 1)

*From raw maps and string queries to fully typed, cached API calls — in one command.*

---

You know that feeling when you're building something in Flutter, the idea is clean, the UI is coming together, and then you open the file where you call your GraphQL API?

```dart
final result = await client.query(
  QueryOptions(
    document: gql(r'''
      query getRecipe($id: ID!) {
        getRecipe(id: $id) {
          id
          title
          description
          prepTimeMinutes
          servings
          chefId
        }
      }
    '''),
    variables: {'id': recipeId},
  ),
);

final data = result.data?['getRecipe'] as Map<String, dynamic>?;
final title = data?['title'] as String?;
final servings = data?['servings'] as int?;
```

Casts. Nullable dynamic maps. A query string living in the middle of your Dart code. No autocomplete. No compile-time safety. If you rename a field in your schema, the compiler says nothing — your app just breaks at runtime.

I got tired of this. So I built something to fix it.

---

## The idea: your schema already knows everything

Think about what a GraphQL schema actually contains. Every type. Every field. Every nullable and non-nullable relationship. Every query argument. The *entire* contract between your frontend and your backend is already written down — in the schema.

So why are we re-writing that contract by hand in Dart? Why are we maintaining query strings, building data classes manually, and casting `dynamic` everywhere?

**[GraphLink](https://graphlink.dev)** reads your schema and generates everything. You get typed Dart classes, a fully typed client, `fromJson`/`toJson` — and you never write any of it yourself.

The generated class names are also plain Dart — no `$` signs, no mangled suffixes. Your code should look like code, not a bash script.

Let me show you exactly what that looks like.

---

## The schema: a recipe app

Here is the complete GraphQL schema for a recipe app. Nothing exotic — types, queries, mutations, and a compound query to fetch a recipe and its chef together.

```graphql
type Chef {
  id: ID!
  name: String!
  bio: String
  country: String!
}

type Recipe {
  id: ID!
  title: String!
  description: String
  prepTimeMinutes: Int!
  servings: Int!
  chefId: ID!
}

input CreateRecipeInput {
  title: String!
  description: String
  prepTimeMinutes: Int!
  servings: Int!
  chefId: ID!
}

type Query {
  getRecipe(id: ID!): Recipe! @glCache(ttl: 300, tags: ["recipes"])
  getChef(id: ID!): Chef!    @glCache(ttl: 600, tags: ["chefs"])
}

type Mutation {
  createRecipe(input: CreateRecipeInput!): Recipe!
    @glCacheInvalidate(tags: ["recipes"])
}

# Compound query — fetches recipe and chef in one round trip.
# Each field has its own cache entry and TTL.
query getRecipeWithChef($recipeId: ID!, $chefId: ID!)
  @glCache(ttl: 300, tags: ["data"]) {
  recipe: getRecipe(id: $recipeId)
    @glCache(ttl: 300, tags: ["recipes"]) { ... _all_fields }
  chef: getChef(id: $chefId)
    @glCache(ttl: 600, tags: ["chefs"]) { ... _all_fields }
}
```

Notice the `@glCache` and `@glCacheInvalidate` directives — I will come back to those. You will also see `... _all_fields` used as a field selector — that is a GraphLink built-in fragment; Part 2 covers it in detail along with custom queries and projections. For now, save this as `schema/recipes.graphql`.

---

## Configure and generate

Create a `config.json` next to your schema:

```json
{
  "schemaPaths": ["schema/*.graphql"],
  "mode": "client",
  "typeMappings": {
    "ID": "String",
    "String": "String",
    "Int": "int",
    "Boolean": "bool",
    "Float": "double"
  },
  "outputDir": "lib/generated",
  "clientConfig": {
    "dart": {
      "packageName": "my_recipe_app",
      "generateAllFieldsFragments": true,
      "autoGenerateQueries": true,
      "httpAdapter": "dio"
    }
  }
}
```

Then run:

```bash
glink -c config.json
```

That is the only command. In about 100ms, your `lib/generated` folder appears:

```
lib/generated/
  client/
    graph_link_client.dart          ← the typed client
    graph_link_dio_adapter.dart     ← generated HTTP adapter (Dio)
  types/
    recipe.dart
    chef.dart
    get_recipe_response.dart
    get_chef_response.dart
    get_recipe_with_chef_response.dart
    create_recipe_response.dart
  inputs/
    create_recipe_input.dart
  enums/
    ...
```

No annotation processors. No `build_runner`. One binary, one command, done.

---

## What got generated

Let's look at what is inside these files, because this is where the magic becomes real.

**`lib/generated/types/recipe.dart`**

```dart
class Recipe {
  final String id;
  final String title;
  final String? description;    // nullable in schema → String? in Dart
  final int prepTimeMinutes;
  final int servings;
  final String chefId;

  Recipe({
    required this.id,
    required this.title,
    this.description,
    required this.prepTimeMinutes,
    required this.servings,
    required this.chefId,
  });

  static Recipe fromJson(Map<String, dynamic> json) => Recipe(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    prepTimeMinutes: json['prepTimeMinutes'] as int,
    servings: json['servings'] as int,
    chefId: json['chefId'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'prepTimeMinutes': prepTimeMinutes,
    'servings': servings,
    'chefId': chefId,
  };
}
```

Plain Dart. No annotation, no dependency on GraphLink at runtime. If you stop using GraphLink tomorrow, this class keeps compiling and working.

**`lib/generated/types/get_recipe_with_chef_response.dart`**

```dart
class GetRecipeWithChefResponse {
  final Recipe recipe;
  final Chef chef;

  GetRecipeWithChefResponse({
    required this.recipe,
    required this.chef,
  });

  static GetRecipeWithChefResponse fromJson(Map<String, dynamic> json) =>
    GetRecipeWithChefResponse(
      recipe: Recipe.fromJson(json['recipe'] as Map<String, dynamic>),
      chef: Chef.fromJson(json['chef'] as Map<String, dynamic>),
    );
}
```

The compound query gets its own response class. Both fields are typed and required — exactly as declared in the schema.

**`lib/generated/inputs/create_recipe_input.dart`**

```dart
class CreateRecipeInput {
  final String title;
  final String? description;
  final int prepTimeMinutes;
  final int servings;
  final String chefId;

  CreateRecipeInput({
    required this.title,
    this.description,
    required this.prepTimeMinutes,
    required this.servings,
    required this.chefId,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'prepTimeMinutes': prepTimeMinutes,
    'servings': servings,
    'chefId': chefId,
  };
}
```

Required fields are `required`. Nullable fields are optional. The compiler enforces this — you cannot call `CreateRecipeInput(title: 'Ratatouille')` and forget `prepTimeMinutes`. It will not compile.

---

## Using the client

Setting up the client is a single line:

```dart
import 'package:my_recipe_app/generated/client/graph_link_client.dart';

final client = GraphLinkClient.withHttp(
  url: 'https://api.myrecipeapp.com/graphql',
);
```

The generated `GraphLinkDioAdapter` handles HTTP. The generated `DefaultGraphLinkWebSocketAdapter` handles subscriptions (with auto-reconnect). You did not write either of them.

### Simple query

```dart
final res = await client.queries.getRecipe(id: '42');

// res.getRecipe is a typed Recipe — no casting
print(res.getRecipe.title);           // Spaghetti Carbonara
print(res.getRecipe.prepTimeMinutes); // 25
print(res.getRecipe.servings);        // 4
```

Your IDE autocompletes every field. If `title` is renamed to `name` in the schema and you regenerate, every call site that still uses `.title` becomes a compile error. You catch the break before your users do.

### Compound query

Here is the part I am most proud of. Two server calls, one typed response, one line of Dart:

```dart
final res = await client.queries.getRecipeWithChef(
  recipeId: '42',
  chefId: 'chef-99',
);

// Both objects are fully typed, no nulls, no casts
print(res.recipe.title);   // Spaghetti Carbonara
print(res.chef.name);      // Massimo Bottura
print(res.chef.country);   // Italy
```

GraphLink built the query string, sent it, deserialized both objects, and handed them back to you strongly typed. You wrote zero of the plumbing.

### Mutation

```dart
final res = await client.mutations.createRecipe(
  input: CreateRecipeInput(
    title: 'Ratatouille',
    prepTimeMinutes: 45,
    servings: 4,
    chefId: 'chef-1',
    // description is optional — omit it or pass it
  ),
);

print(res.createRecipe.id);    // server-assigned ID
print(res.createRecipe.title); // Ratatouille
```

---

## Caching: the part that surprised me

This is where GraphLink does something I have not seen in any other Flutter GraphQL client.

Look at the schema again:

```graphql
type Query {
  getRecipe(id: ID!): Recipe! @glCache(ttl: 300, tags: ["recipes"])
  getChef(id: ID!): Chef!    @glCache(ttl: 600, tags: ["chefs"])
}

type Mutation {
  createRecipe(input: CreateRecipeInput!): Recipe!
    @glCacheInvalidate(tags: ["recipes"])
}
```

The caching behavior is declared in the schema itself. `@glCache(ttl: 300, tags: ["recipes"])` means: cache this result for 5 minutes and tag it as `"recipes"`. `@glCacheInvalidate(tags: ["recipes"])` on the mutation means: when this mutation completes, evict everything tagged `"recipes"`.

The generated client handles this automatically — no extra code on your side:

```dart
// First call — hits the server
final res1 = await client.queries.getRecipe(id: '42');

// Second call within 5 minutes — served from cache, no network request
final res2 = await client.queries.getRecipe(id: '42');

// This mutation invalidates the "recipes" cache tag
await client.mutations.createRecipe(input: CreateRecipeInput(
  title: 'Bouillabaisse',
  prepTimeMinutes: 90,
  servings: 6,
  chefId: 'chef-3',
));

// Next call hits the server again — cache was busted
final res3 = await client.queries.getRecipe(id: '42');
```

Now here is where the compound query becomes genuinely interesting. The `getRecipeWithChef` query has **per-field caching**:

```graphql
query getRecipeWithChef($recipeId: ID!, $chefId: ID!) {
  recipe: getRecipe(id: $recipeId)
    @glCache(ttl: 300, tags: ["recipes"]) { ... _all_fields }
  chef: getChef(id: $chefId)
    @glCache(ttl: 600, tags: ["chefs"]) { ... _all_fields }
}
```

What this means: each field is cached independently. If `createRecipe` runs and busts the `"recipes"` tag, the next call to `getRecipeWithChef` fetches only the recipe from the server — the chef is still valid in cache and never leaves the device.

From your Flutter code, none of this is visible. You just call `getRecipeWithChef`. The client figures out what is stale, fetches only that, merges the result, and returns a complete typed response.

---

## Putting it in a Flutter widget

```dart
class RecipeDetailPage extends StatelessWidget {
  final String recipeId;
  final String chefId;

  const RecipeDetailPage({
    required this.recipeId,
    required this.chefId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: client.queries.getRecipeWithChef(
        recipeId: recipeId,
        chefId: chefId,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();

        final recipe = snapshot.data!.recipe;
        final chef = snapshot.data!.chef;

        return Column(
          children: [
            Text(recipe.title, style: Theme.of(context).textTheme.headlineMedium),
            Text('By ${chef.name} · ${chef.country}'),
            Text('${recipe.prepTimeMinutes} min · ${recipe.servings} servings'),
            if (recipe.description != null) Text(recipe.description!),
          ],
        );
      },
    );
  }
}
```

No cast. No null-check on a dynamic map. No string field names that silently break when the schema changes. Just `snapshot.data!.recipe.title`.

---

## What GraphLink does not do

GraphLink is a **code generator**, not a runtime library. It acts like a typed HTTP client — fetch data, get a strongly typed response, do whatever you want with it. There is no reactive store or Apollo-style `watchQuery`. You own the data flow. Pair the generated client with `StreamBuilder`, `ValueNotifier`, Riverpod, or Bloc — whatever state management you already use.

The caching layer is powerful and granular: it is tag-based and schema-driven, declared directly in your `.graphql` files. GraphLink generates an in-memory cache store for you out of the box, or you can plug in your own by implementing a single interface:

```dart
abstract class GraphLinkCacheStore {
  Future<void> set(String key, String value);
  Future<String?> get(String key);
  Future<void> invalidate(String key);
  Future<void> invalidateAll();
}
```

Implement this with SQLite or `SharedPreferences` and your cache survives app restarts — no network call needed on the next cold launch if the data is still within its TTL.

The absence of a runtime dependency means your generated code is yours forever.

---

## Try it

Install the CLI:

```bash
# macOS (ARM)
curl -fsSL https://github.com/Oualitsen/graphlink/releases/latest/download/glink-macos-arm64 -o glink
chmod +x glink && sudo mv glink /usr/local/bin/glink
```

Linux, Windows, and x86 binaries are available on the [releases page](https://github.com/Oualitsen/graphlink/releases/latest).

Then:

```bash
glink -c config.json         # generate once
glink -c config.json -w      # watch mode — regenerates on every schema save
```

Full docs at **[graphlink.dev](https://graphlink.dev)**. The project is open source under the MIT license: **[github.com/Oualitsen/graphlink](https://github.com/Oualitsen/graphlink)**.

If your Flutter app talks to a GraphQL API and you are still writing query strings by hand, try this. The first `glink` run is the last time you write that boilerplate.

---

## One small ask

I built GraphLink to scratch my own itch — I was tired of the boilerplate and nothing out there solved it the way I wanted. If this resonates with you, the most helpful thing you can do is **[star the repo on GitHub](https://github.com/Oualitsen/graphlink)**. It takes two seconds and it genuinely helps the project get noticed.

If you run into something broken, missing, or confusing — [open an issue](https://github.com/Oualitsen/graphlink/issues). Questions and feedback are just as welcome as bug reports. This is early and your experience shapes what gets built next.

---

## Coming in Part 2

We have been using `... _all_fields` as a shorthand to select every field on a type — but GraphLink gives you full control over projections. In Part 2 we will look at how to declare custom queries with explicit field selection, what classes get generated for each projection, and how to use multiple projections of the same type in the same codebase without conflicts.
