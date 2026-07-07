import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/code_name_mixin.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/parser_extensions/gl_expand_grammar_extension.dart';

class GLTypeDefinition extends GLTokenWithFields with GLDirectivesMixin, CodeNameMixin {
  @override
  String get wireName => token;
  final Map<String, TokenInfo> _interfaceNames = {};
  final Map<String, GLInterfaceDefinition> _interfaces = {};
  final bool nameDeclared;
  final GLTypeDefinition? derivedFromType;
  final bool isResponseType;

  final Set<String> _originalTokens = <String>{};

  // @glStrict — memoized result of toProjectionInterface(), so the
  // <Type>Projection interface is synthesized only once per type.
  GLInterfaceDefinition? _projectionInterface;

  // @glStrict — true only for the synthesized GL<Type>Projection interface
  // returned by toProjectionInterface(). Lets serializers distinguish a
  // projection interface (own all-nullable fields, emit as a normal
  // interface) from a real GraphQL `interface`/`union` (TS: union alias).
  bool isServerProjection = false;

  /// Resolved `@glSkipOnServer(mapTo: "X")` target (a type or interface — both
  /// are `GLTypeDefinition`), or `null` if this type has no such mapping.
  /// Populated once in server mode by `populateMappedToTypes()` right after
  /// `validateSkipOnServerMapTo()` / `validateTypeFieldSkipOnServerDirectives()`
  /// confirm the mapping is valid — never computed in client mode.
  GLTypeDefinition? mappedToType;

  GLTypeDefinition({
    required TokenInfo name,
    required this.nameDeclared,
    required List<GLField> fields,
    required Set<TokenInfo> interfaceNames,
    required List<GLDirectiveValue> directives,
    required this.derivedFromType,
    required bool extension,
    this.isResponseType = false,
    String? documentation,
  }) : super(name, extension, fields, documentation: documentation) {
    directives.forEach(addDirective);
    fields.sort((f1, f2) => f1.name.token.compareTo(f2.name.token));
    interfaceNames.forEach(addInterfaceName);
  }

  Set<GLInterfaceDefinition> get interfaces => Set.unmodifiable(_interfaces.values);
  Set<TokenInfo> get interfaceNames => Set.unmodifiable(_interfaceNames.values);
  Set<String> get originalTokens => Set.unmodifiable(_originalTokens);

  void addInterfaceName(TokenInfo token) {
    _interfaceNames[token.token] = token;
  }

  void addInterface(GLInterfaceDefinition iface) {
    _interfaces[iface.token] = iface;
    addInterfaceName(iface.tokenInfo);
    iface.addImplementation(this);
    _isOverrideCache.clear();
  }

  void unlinkInterface(GLInterfaceDefinition iface) {
    _interfaces.remove(iface.token);
    _interfaceNames.remove(iface.token);
    _isOverrideCache.clear();
  }

  void addOriginalToken(String token) {
    _originalTokens.add(token);
  }

  ///
  ///check is the two definitions will produce the same object structure
  ///
  bool isSimilarTo(GLTypeDefinition other, GLParser g) {
    var dft = derivedFromType;
    var otherDft = other.derivedFromType;
    if (otherDft != null) {
      if ((dft?.tokenInfo ?? tokenInfo) != otherDft.tokenInfo) {
        return false;
      }
    }
    return getHash(g) == other.getHash(g);
  }

  bool implements(String interfaceName) {
    return _interfaceNames[interfaceName] != null;
  }

  final Map<String, bool> _isOverrideCache = {};

  /// True when [field] is also declared on one of this type's interfaces
  /// (including synthesized `GL<Type>Projection` interfaces from
  /// `@glStrict`), i.e. it is an override rather than a field unique to
  /// this type.
  bool isOverride(GLField field) {
    return _isOverrideCache[field.name.token] ??= _interfaces.values.any((iface) => iface.hasField(field.name.token));
  }

  /// Returns the declaration of [field] on the first of this type's
  /// interfaces that declares it, or `null` if [field] is not an override.
  /// Lets serializers match an overriding member's signature (nullability,
  /// accessor naming, …) to the interface's declared shape rather than this
  /// type's own (possibly narrowed) shape.
  GLField? getInterfaceField(GLField field) {
    for (final iface in _interfaces.values) {
      final f = iface.getFieldByName(field.name.token);
      if (f != null) return f;
    }
    return null;
  }

  String? _cachedHash;

  String getHash(GLParser g) {
    if (_cachedHash != null) return _cachedHash!;
    var serilaize = GLGraphqlSerializer(g);
    final fields = [...getSerializableFields(g.mode)];

    // Client mode: a depth-truncated projection of a cyclic type drops the
    // cyclic edge(s), so it would otherwise hash differently from the full
    // projection. Back-fill the missing cyclic edges from the derived-from type
    // (as nullable, matching how the full projection emits them) so both shapes
    // hash identically and the dedup pass can collapse them into one type.
    //
    // Only fires for DERIVED projections (`derivedFromType != null`): the
    // abstract-mediated (interface/union) cyclic types that take the projection
    // slow path. Verified load-bearing — disabling it leaves duplicate
    // truncated/full shapes (e.g. Item vs Item_IdValue, Person vs Person_IdName)
    // that fail to dedup. It is a no-op for pure-object cycles: there
    // forceCyclicEdgesNullable + the all-fields fast path register the declared
    // type directly (derivedFromType is null), so the loop is skipped.
    final origin = derivedFromType;
    if (g.mode == CodeGenerationMode.client && origin != null) {
      final present = fields.map((f) => f.name.token).toSet();
      for (final sf in origin.getSerializableFields(g.mode)) {
        if (present.contains(sf.name.token)) continue;
        if (!g.typeRequiresProjection(sf.type)) continue;
        if (!g.isFieldCyclic(origin.token, sf.type.inlineType.token)) continue;
        fields.add(sf);
      }
    }

    fields.sort((a, b) => a.name.token.compareTo(b.name.token));
    _cachedHash = fields
        .map((f) => "${f.name}:${serilaize.serializeType(f.type, forceNullable: f.hasInculeOrSkipDiretives || _isBackfilledCyclic(f, origin, g))}")
        .join(",");
    return _cachedHash!;
  }

  /// True for a derived-from cyclic edge we back-filled above (not actually a
  /// field of this projection) — those are emitted nullable in the real
  /// projection, so the hash must serialize them nullable too.
  bool _isBackfilledCyclic(GLField f, GLTypeDefinition? origin, GLParser g) {
    if (origin == null || g.mode != CodeGenerationMode.client) return false;
    if (fields.any((own) => own.name.token == f.name.token)) return false;
    return g.typeRequiresProjection(f.type) && g.isFieldCyclic(origin.token, f.type.inlineType.token);
  }

  Set<String> getIdentityFields(GLParser g) {
    var directive = getDirectiveByName(glEqualsHashcode);
    if (directive != null) {
      var directiveFields =
          (directive.getArguments().first.value as List).map((e) => e as String).map((e) => e.replaceAll('"', '').replaceAll("'", "")).toSet();
      return directiveFields.where((e) => fieldNames.contains(e)).toSet();
    }
    return g.identityFields.where((e) => fieldNames.contains(e)).toSet();
  }

  @override
  String toString() {
    return 'GraphqlType{name: $tokenInfo, fields: $fields, interfaceNames: $interfaceNames}';
  }

  List<GLField> getFields() {
    return [...fields];
  }

  bool containsInteface(String interfaceName) => _interfaceNames[interfaceName] != null;

  Set<String> getInterfaceNames() => _interfaceNames.keys.toSet();

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    var result = {...super.getImportDependecies(g)};

    for (var iface in _interfaces.values) {
      var token = g.getTokenByKey(iface.token);
      if (filterDependecy(token, g)) {
        result.add(token!);
      }
    }
    return result;
  }

  @override
  void merge<T extends GLExtensibleToken>(T other) {
    if (other is GLTypeDefinition) {
      other.getDirectives().forEach(addDirective);
      other.fields.forEach(addOrMergeField);
    }
  }

  ///
  /// @glStrict — synthesizes the `<Type>Projection` interface: every
  /// serializable field cloned as all-nullable with zero directives, and any
  /// field referencing another object/interface/union rewritten to
  /// `<FieldType>Projection`. Built lazily and cached — calling this more
  /// than once always returns the same instance.
  ///
  GLInterfaceDefinition toProjectionInterface(GLParser g) {
    final cached = _projectionInterface;
    if (cached != null) return cached;

    final projectedFields = getSerializableFields(CodeGenerationMode.server).map((f) => _toProjectionField(f, g)).toList();
    var skipOnServerDirective = getDirectiveByName(glSkipOnServer);

    final projection = GLInterfaceDefinition(
      name: tokenInfo.ofNewName(serverProjectionName),
      nameDeclared: false,
      fields: projectedFields,
      directives: skipOnServerDirective == null ? const [] : [_toProjectionSkipOnServerDirective(skipOnServerDirective, g)],
      interfaceNames: const {},
      extension: false,
    );
    projection.isServerProjection = true;

    _projectionInterface = projection;
    return projection;
  }

  String get serverProjectionName => getServerProjectionName(token);

  static String getServerProjectionName(String token) {
    return "GL${token}Projection";
  }

  GLField _toProjectionField(GLField f, GLParser g) {
    var skipOnServerDirective = f.getDirectiveByName(glSkipOnServer);
    var skipOnClientDirective = f.getDirectiveByName(glSkipOnClient);
    return GLField(
      name: f.name,
      type: _toProjectionFieldType(f.type, g),
      arguments: f.arguments,
      initialValue: f.initialValue,
      documentation: f.documentation,
      directives: [
        if (skipOnServerDirective != null) _toProjectionSkipOnServerDirective(skipOnServerDirective, g),
        if (skipOnClientDirective != null) skipOnClientDirective,
      ],
    );
  }

  /// Rewrites the field's own type to all-nullable, recursing into list
  /// types so that only the outermost type becomes nullable (matching
  /// `List<XProjection>?`, not `List<XProjection?>?`).
  GLType _toProjectionFieldType(GLType type, GLParser g) {
    final rewritten = _rewriteProjectionTypeRef(type, g);
    if (rewritten is GLListType) {
      return GLListType(rewritten.type, true);
    }
    return GLType(rewritten.tokenInfo, true);
  }

  /// Clones an existing `@glSkipOnServer(mapTo: "X", ...)` directive, rewriting
  /// `mapTo` to `GL<X>Projection` when `X` names a type or interface — all
  /// other arguments and the directive itself are left unchanged.
  GLDirectiveValue _toProjectionSkipOnServerDirective(GLDirectiveValue skipOnServer, GLParser g) {
    final mapTo = skipOnServer.getArgValueAsString(glMapTo);
    if (mapTo == null || !(g.types.containsKey(mapTo) || g.interfaces.containsKey(mapTo))) {
      return skipOnServer;
    }

    final newArgs = skipOnServer.getArguments().map((arg) {
      if (arg.token == glMapTo) {
        return GLArgumentValue(arg.tokenInfo, '"${getServerProjectionName(mapTo)}"');
      }
      return arg;
    }).toList();

    return GLDirectiveValue(
      skipOnServer.tokenInfo,
      skipOnServer.locations,
      newArgs,
      generated: skipOnServer.generated,
    );
  }

  /// Rewrites object/interface/union type references to `<Type>Projection`,
  /// recursing into list element types, without touching nullability.
  GLType _rewriteProjectionTypeRef(GLType type, GLParser g) {
    if (type is GLListType) {
      return GLListType(_rewriteProjectionTypeRef(type.type, g), type.nullable);
    }
    if (g.typeRequiresProjection(type)) {
      return GLType(type.tokenInfo.ofNewName(GLTypeDefinition.getServerProjectionName(type.token)), type.nullable);
    }
    return type;
  }
}
