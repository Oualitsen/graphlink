# TypeScript toJson/fromJson in namespaces

## Problem

TypeScript generated types currently have no toJson/fromJson serialization
functions. This blocks field-name normalization (e.g. camelCase `User` → `user`)
because the server sends wire names (`"User"`) in JSON, but the TS interface
declares `user`, and without a mapping layer, `response.user` is `undefined`.

Dart, Java, and Kotlin serializers all generate toJson/fromJson that bridge wire
names and code names. This plan adds the same for TypeScript using `namespace`
blocks merged with each type/input/enum declaration.

## Design

Each emitted file gets a namespace alongside the type/input/enum:

```typescript
export interface User {
  readonly id: string;
  name?: string | null;
  readonly role: Role;
}

export namespace User {
  export function toJson(obj: User): Record<string, unknown> {
    return {
      id: obj.id,
      name: obj.name,
      role: Role.toJson(obj.role),
    };
  }
  export function fromJson(json: Record<string, unknown>): User {
    return {
      id: json["id"] as string,
      name: json["name"] as string | null,
      role: json["role"] != null ? Role.fromJson(json["role"] as string) : null,
    };
  }
}
```

For enums with keyword-renamed values:

```typescript
export enum Action {
  return_ = 'return',
  cancel = 'cancel',
}

export namespace Action {
  export function toJson(value: Action): string { return value; }
  export function fromJson(value: string): Action {
    switch (value) {
      case "return": return Action.return_;
      case "cancel": return Action.cancel;
      default: throw new Error("Invalid Action: " + value);
    }
  }
}
```

For GraphQL interfaces (which become TS union type aliases):

```typescript
export type Animal = Dog | Cat;

export namespace Animal {
  export function fromJson(json: Record<string, unknown>): Animal {
    switch (json["__typename"] as string) {
      case "Dog": return Dog.fromJson(json);
      case "Cat": return Cat.fromJson(json);
      default: throw new Error("Unknown Animal: " + json["__typename"]);
    }
  }
}
```

## Nullable handling

- **Scalars**: `json["field"] as string | null` (Dart `as String?`)
- **Enums**: `json["field"] != null ? Role.fromJson(json["field"] as string) : null`
- **Projectable types**: `json["field"] != null ? Type.fromJson(json["field"] as Record<string, unknown>) : null`
- **Lists**: `json["field"] != null ? (json["field"] as unknown[]).map(e => transform) : null`

The `!= null` guard on enums and projectable types prevents passing `null` into
their fromJson functions. Scalars use `as T | null` since TS `as` is a pure type
assertion with no runtime cost.

## Files to change

### `lib/src/typescript_code_gen_utils.dart`

Add `createNamespace` method:

```dart
String createNamespace({
  required String namespaceName,
  required List<String> statements,
  bool exported = true,
})
```

### `lib/src/serializers/typescript_serializer.dart`

**Constructor**: Replace hardcoded `bool get generateJsonMethods => false` with
a `final bool generateJsonMethods` field defaulting `true`.

**`doSerializeField`** (line 156): Switch `final name = def.name` to
`final name = def.codeName`.

**New methods** (modeled on `dart_serializer.dart`):

| Method | Purpose |
|---|---|
| `_generateTypeToJson(fields)` | toJson function body |
| `_generateTypeFromJson(fields, token)` | fromJson function body |
| `_fieldToJsonExpr(field)` | One field: `"wireKey": codeName<transform>` |
| `_fieldFromJsonExpr(field)` | One field: `codeName: <transform>` |
| `_callToJson(varName, type, depth)` | Recursive toJson for nested types/lists |
| `_callFromJson(varName, type, depth)` | Recursive fromJson for nested types/lists |
| `_generateEnumToJson(def)` | Enum toJson |
| `_generateEnumFromJson(def)` | Enum fromJson (switch-based) |
| `_serializeUnionFromJson(def)` | Union fromJson (__typename dispatch) |

**Hooks**: `_serializeType`, `doSerializeInputDefinition`,
`doSerializeEnumDefinition`, and `_serializeInterfaceAsUnion` each append the
namespace block when `generateJsonMethods` is true.

## Testing

Add a test in `test/keywords/` with a schema containing types with fields of
various kinds (scalar, enum, nested type, list, nullable), serialize them, and
assert the namespace functions appear with correct wire-name/code-name split.

Run existing TS tests to catch regressions:

```bash
fvm dart test test/keywords/typescript_keyword_enum_test.dart > /tmp/ts.log 2>&1; grep -E "FAILED|passed" /tmp/ts.log
fvm dart test test/keywords/typescript_keyword_field_test.dart > /tmp/ts2.log 2>&1; grep -E "FAILED|passed" /tmp/ts2.log
```
