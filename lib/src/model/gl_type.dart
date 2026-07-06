import 'package:graphlink/src/model/gl_collection_imports.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/token_info.dart';

class GLType extends GLToken {
  /// Target-language `List`/`Map` import strings. Set once by [GLParser]'s
  /// constructor from the generator config; read lazily by
  /// [collectionImportsOf] so no eager tree-walk over every field/argument
  /// type is needed.
  static GLCollectionImports collectionImportsConfig = GLCollectionImports.none;

  final bool nullable;

  /// Optional target-language wrapper type name this type should be rendered
  /// inside (e.g. `Mono`, `Flux`, `Uni`) — null means render the type as-is.
  /// Set by server/reactive serializers; never populated from a parsed
  /// `.graphql` schema.
  String? wrapper;

  /// Fully-qualified import required for [wrapper], if any.
  String? wrapperImport;


  /// needed when this type is not generated,
  ///  the type is from a framework or external class that is not managed by graphlink
  String? externalImport;

  GLType(super.tokenInfo, this.nullable, {this.wrapper, this.wrapperImport, this.externalImport});

  @override
  bool operator ==(Object other) {
    if (other is GLType) {
      return tokenInfo.token == other.tokenInfo.token && nullable == other.nullable;
    }
    return false;
  }

  GLType get inlineType => this;
  GLType get firstType => this;

  bool get isList => this is GLListType;

  bool get isNotList => !isList;

  @override
  int get hashCode => Object.hash(tokenInfo.token, nullable);

  GLType ofNewName(TokenInfo name) {
    return GLType(name, nullable, wrapper: wrapper, wrapperImport: wrapperImport);
  }

  /// An independent structural copy of this type — same token/nullability,
  /// but a distinct object so mutating one instance's [wrapper] (e.g. a
  /// controller wrapping a field's return type in `CompletableFuture`) can
  /// never leak into another owner (e.g. the originating service field)
  /// sharing the same [GLType] instance.
  GLType get copy => ofNewName(tokenInfo);

  /// Returns a copy of [type] with the outermost nullability forced to true.
  /// For list types only the outer wrapper is relaxed — `[T!]!` → `[T!]?`.
  static GLType makeNullable(GLType type) {
    if (type is GLListType) return GLListType(type.type, true);
    return GLType(type.tokenInfo, true);
  }
}

/// Target-language `List`/`Map` import strings needed by [type] and every
/// nested type — e.g. the `List` import for `[[Foo]]`, or the `Map` import
/// together with both bounds' imports for a map type. Reads
/// [GLType.collectionImportsConfig], set once by [GLParser]'s constructor.
Set<String> collectionImportsOf(GLType type) {
  final wrapperImport = type.wrapperImport;
  if (type is GLMapType) {
    return {
      if (GLType.collectionImportsConfig.mapImport != null)
        GLType.collectionImportsConfig.mapImport!,
      if (wrapperImport != null) wrapperImport,
      ...collectionImportsOf(type.keyType),
      ...collectionImportsOf(type.valueType),
    };
  }
  if (type is GLListType) {
    return {
      if (GLType.collectionImportsConfig.listImport != null)
        GLType.collectionImportsConfig.listImport!,
      if (wrapperImport != null) wrapperImport,
      ...collectionImportsOf(type.inlineType),
    };
  }
  return {
    ...type.staticImports,
    if (wrapperImport != null) wrapperImport,
  };
}

/// A synthetic map type used for the server-side return type of batch
/// `@BatchMapping` service methods (`Map<Key, Value>`). Never appears in a
/// parsed `.graphql` schema — it's built by the JVM server serializers,
/// so it must never be emitted back into generated GraphQL SDL.
class GLMapType extends GLType {
  final GLType keyType;
  final GLType valueType;

  /// Copies [keyType]/[valueType] rather than storing the passed-in instances
  /// directly. Callers routinely build a `GLMapType` around a type that's
  /// also owned elsewhere (e.g. a batch mapping's per-item field type, held
  /// both as the map's value type and as its own field's type) — later
  /// in-place mutation of one owner's `wrapper`/`wrapperImport` (e.g. the
  /// reactive-wrapping pass) must never leak into the other. See
  /// [GLType.copy].
  GLMapType(GLType keyType, GLType valueType, bool nullable, {String? wrapper, String? wrapperImport})
      : keyType = keyType.copy,
        valueType = valueType.copy,
        super(valueType.tokenInfo, nullable, wrapper: wrapper, wrapperImport: wrapperImport);

  @override
  GLType ofNewName(TokenInfo name) {
    return GLMapType(keyType, valueType.ofNewName(name), nullable,
        wrapper: wrapper, wrapperImport: wrapperImport);
  }

  @override
  int get hashCode => Object.hash(keyType, valueType, nullable);

  @override
  bool operator ==(Object other) {
    if (other is GLMapType) {
      return keyType == other.keyType &&
          valueType == other.valueType &&
          nullable == other.nullable;
    }
    return false;
  }
}

class GLListType extends GLType {
  ///this could be an instance of GQListType
  final GLType type;

  /// Copies [type] rather than storing the passed-in instance directly, for
  /// the same reason as [GLMapType]'s constructor: a caller may build a
  /// `GLListType` around an element type that's also owned elsewhere, and
  /// later in-place mutation of one owner's `wrapper`/`wrapperImport` must
  /// never leak into the other. See [GLType.copy].
  GLListType(GLType type, bool nullable, {String? wrapper, String? wrapperImport})
      : type = type.copy,
        super(type.tokenInfo, nullable, wrapper: wrapper, wrapperImport: wrapperImport);

  @override
  GLType get inlineType => type;

  @override
  GLType ofNewName(TokenInfo name) {
    return GLListType(type.ofNewName(name), nullable,
        wrapper: wrapper, wrapperImport: wrapperImport);
  }

  ///
  /// a recursive way to find the first TYPE even if this is a list of list of list .... of list of TYPE
  ///
  @override
  GLType get firstType => type.firstType;

  @override
  int get hashCode => Object.hash(tokenInfo.token, type, nullable);

  @override
  bool operator ==(Object other) {
    if (other is GLListType) {
      return type == other.type && nullable == other.nullable;
    }
    return false;
  }
}
