import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_query_element.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/utils.dart';
import 'package:graphlink/src/gl_expand_grammar_extension.dart';

/// Deterministic djb2 hash — same input always produces the same output.
int _djb2(String s) {
  int hash = 5381;
  for (final c in s.codeUnits) {
    hash = (((hash << 5) + hash) + c) & 0xFFFFFFFF;
  }
  return hash;
}

final Map<String, List<GLTypeDefinition>> _typeHashIndex = {};
final Map<String, List<GLTypeDefinition>> _interfaceHashIndex = {};

/// A single field-argument `$variable` reference discovered while walking an
/// operation's selection set, carrying everything [_addGeneratedArgument] needs
/// to register it on a query definition.
class _GeneratedArgSpec {
  final String varToken;
  final GLArgumentDefinition argDef;
  final GLField field;
  final GLProjection projection;

  const _GeneratedArgSpec(
      this.varToken, this.argDef, this.field, this.projection);
}

extension GLGrammarProjectionExtension on GLParser {
  void fillInterfaceImplementations() {
    var ifaces = interfaces.values;
    for (var iface in ifaces) {
      var types = getTypesImplementing(iface);
      types.forEach(iface.addImplementation);
    }
  }

  void updateInterfaceReferences() {
    var allTypes = [...interfaces.values, ...types.values];
    allTypes.where((type) => type.interfaceNames.isNotEmpty).forEach((type) {
      var result =
          type.interfaceNames.map((token) => getInterface(token.token, token));
      result.forEach(type.addInterface);
    });
  }

  /// GraphQL requires a type/interface to explicitly declare every interface
  /// transitively implemented by its own declared interfaces (spec
  /// "IsValidImplementation"), not just the ones it names directly. Mirrors
  /// [handleFragmentDepenecy]'s dependency-closure approach: walk each
  /// type/interface's own `.interfaces` graph with a seen-set and add every
  /// interface reachable, however deep. Must run after any step that adds new
  /// `implements` edges (`updateInterfaceReferences`, `populateServerProjections`)
  /// since it only closes over edges already present at call time.
  void fillTransitiveInterfaceImplementations() {
    var allTypes = [...interfaces.values, ...types.values];
    for (var type in allTypes) {
      var seen = <String>{type.token};
      var queue = [...type.interfaces];
      while (queue.isNotEmpty) {
        var iface = queue.removeLast();
        if (!seen.add(iface.token)) continue;
        type.addInterface(iface);
        queue.addAll(iface.interfaces);
      }
    }
  }

  void _updateInterfaceCommonFields(List<GLInterfaceDefinition> definitions) {
    for (var i in definitions) {
      var commonFields = _getCommonInterfaceFields(i);
      for (var cf in commonFields) {
        i.addField(cf);
      }
    }
  }

  void _fillProjectedInterfaces(List<GLInterfaceDefinition> interfaces) {
    for (var iface in interfaces) {
      var projections = iface.fields.map((field) => GLProjection(
          fragmentName: null,
          token: field.name,
          alias: null,
          block: null,
          directives: []));
      var newName = _generateName(iface.derivedFromType!.token, projections, []);
      var newIface = GLInterfaceDefinition(
        name: iface.tokenInfo.ofNewName(newName.value),
        nameDeclared: newName.declared,
        fields: iface.fields,
        directives: iface.getDirectives(),
        interfaceNames: iface.interfaceNames,
        extension: false,
      );
      iface.implementations.forEach(newIface.addImplementation);
      var added = addToProjectedTypes(newIface) as GLInterfaceDefinition;
      iface.implementations.forEach(added.addImplementation);
      for (var impl in added.implementations) {
        impl.addInterface(added);
      }
    }
  }

  /// need to remove all implementations from interfaces that has been replaced by similar objects
  void cleanProjectedInterfacesImplementations() {
    for (var iface in projectedInterfaces.values) {
      iface.implementations
          .map((e) => e.token)
          .where((token) => !projectedTypes.containsKey(token))
          .toSet()
          .forEach(iface.removeImplementation);
    }
  }

  void addClientTypesToProjectedTypes() {
    for (var type in clientTypes) {
      var t = types[type];
      if (t != null) {
        projectedTypes[type] = t;
      }
    }

    for (var type in clientInterfaces) {
      var result = types[type] ?? interfaces[type];
      if (result != null) {
        if (result is GLInterfaceDefinition) {
          projectedInterfaces[type] = result;
        } else {
          projectedTypes[type] = result;
        }
      }
    }
  }

  List<GLField> _getCommonInterfaceFields(GLInterfaceDefinition def) {
    // search in projected types, types that have implemented this interface
    var types = def.implementations;
    if (types.isEmpty) {
      return [];
    }
    var map = <String, int>{};
    var token = def.derivedFromType!.token;
    final iface = (interfaces[token] ?? projectedInterfaces[token])!;
    final fields = iface.fields;
    var interfaceFieldNames = iface.fields.map((f) => f.name.token).toSet();

    types.expand((t) => t.fields).forEach((f) {
      if (map.containsKey(f.name.token)) {
        map[f.name.token] = map[f.name.token]! + 1;
      } else {
        map[f.name.token] = 1;
      }
    });

    var result = <GLField>[];
    map.forEach((fieldName, count) {
      if (count == types.length && interfaceFieldNames.contains(fieldName)) {
        result.addAll(fields.where((f) => f.name.token == fieldName));
      }
    });
    return result;
  }

  void createProjectedTypes() {
    _typeHashIndex.clear();
    _interfaceHashIndex.clear();
    // pre-populate index with static schema types so findSimilarTo covers them
    for (var t in typesWithNoResolvers) {
      _typeHashIndex.putIfAbsent(t.getHash(this), () => []).add(t);
    }
    for (var i in interfaces.values) {
      _interfaceHashIndex.putIfAbsent(i.getHash(this), () => []).add(i);
    }
   

    final allEmenets = getAllElements();

    allEmenets.where((e) => e.block != null).forEach((element) {
      var newType = createProjectedTypeForQuery(element);
      element.projectedTypeKey = newType.token;
    });

    allEmenets.where((e) => e.projectedTypeKey != null).forEach((element) {
      var returnTypeToken = element.returnType.token;
      if(interfaces.containsKey(returnTypeToken)) {
        element.projectedType = projectedInterfaces[element.projectedTypeKey!]!;
      }else {
        element.projectedType = projectedTypes[element.projectedTypeKey!]!;
      }
    });

    queries.forEach((key, query) {
      // The generated wrappers (`<stem>Response` / `<stem>FullResponse`, both
      // flagged isResponseType) share the same name space as user-declared
      // types. Pick a collision-free stem before the definitions are built so
      // the auto `<Field>Response` name doesn't clash with a declared type
      // (e.g. GitLab declares `type VulnerabilityResponse`, which collides with
      // the auto-generated `vulnerability` query wrapper).
      _assignCollisionFreeResponseStem(query);

      var projectedType = query.getGeneratedTypeDefinition();
      if (projectedTypes.containsKey(projectedType.token)) {
        throw ParseException(
            "Type ${projectedType.tokenInfo.token} has already been defined, please rename it",
            info: projectedType.tokenInfo);
      }
      var def = addToProjectedTypes(projectedType, similarityCheck: false);
      query.updateTypeDefinition(def);


      var fullResponseType = query.getFullResponseTypeDefinition(this);
      if (projectedTypes.containsKey(fullResponseType.token)) {
        throw ParseException(
            "Type ${fullResponseType.tokenInfo.token} has already been defined, please rename it",
            info: projectedType.tokenInfo);
      }
      addToProjectedTypes(fullResponseType, similarityCheck: false);
    });

    // ignore: avoid_print
   // print('[createProjectedTypes] TOTAL: ${_swTotal.elapsedMilliseconds}ms');
  }

  /// Gives [query] a `<stem>` for its generated `<stem>Response` /
  /// `<stem>FullResponse` wrapper types (both [GlTypeDefinition.isResponseType])
  /// such that neither name collides with an already-known type name.
  ///
  /// The default `<Field>` stem is kept whenever it is free — so existing
  /// schemas (and the client code generated for them) keep their current
  /// `<Field>Response` names with no churn. Only on collision do we fall back
  /// deterministically to `<Field><Operation>` (e.g. `VulnerabilityQuery`),
  /// then to a numeric suffix. Queries that pin their name via a directive
  /// (`@glName`) are honoured as-is and left untouched.
  void _assignCollisionFreeResponseStem(GLQueryDefinition query) {
    if (query.hasDeclaredResponseName) return;

    final base = query.defaultGeneratedNameStem;
    if (_responseStemIsFree(base)) return; // common case — keep <Field>Response

    final withOp = '$base${query.type.name.firstUp}';
    if (_responseStemIsFree(withOp)) {
      query.overrideGeneratedNameStem(withOp);
      return;
    }

    var i = 2;
    while (!_responseStemIsFree('$withOp$i')) {
      i++;
    }
    query.overrideGeneratedNameStem('$withOp$i');
  }

  /// A [stem] is usable only when BOTH derived names (`<stem>Response` and
  /// `<stem>FullResponse`) are free, so the data wrapper and its full-response
  /// wrapper stay consistent under a single stem.
  bool _responseStemIsFree(String stem) =>
      !_typeNameTaken('${stem}Response') &&
      !_typeNameTaken('${stem}FullResponse');

  /// True when [name] is already used by a type or interface (declared or
  /// projected) — the only definitions that can be [isResponseType], and thus
  /// the only name spaces an auto-generated response wrapper can collide with.
  bool _typeNameTaken(String name) =>
      types.containsKey(name) ||
      interfaces.containsKey(name) ||
      projectedTypes.containsKey(name) ||
      projectedInterfaces.containsKey(name);

  /// True when, ignoring an implicit `__typename`, [projectionMap] is exactly
  /// one generated all-fields spread — i.e. the field selects the whole type.
  /// `__typename` is excluded because it is auto-injected into interface/union
  /// (inline-fragment) blocks for `fromJson` dispatch, so the spread is not
  /// necessarily the map's only entry. See [GLProjection.allFieldsSpread].
  bool _isSoleAllFieldsSpread(Map<String, GLProjection> projectionMap) {
    GLProjection? spread;
    for (final entry in projectionMap.entries) {
      if (entry.key == GLParser.typename) continue;
      if (spread != null) return false; // more than one real selection
      spread = entry.value;
    }
    return spread != null && spread.allFieldsSpread;
  }

  /// Registers [type] and everything reachable from it directly into the
  /// projected stores, skipping the field-rebuild + hash + similarity work. Safe
  /// because the all-fields projection of a (cyclic-edge-relaxed) declared type
  /// is structurally the declared type itself.
  ///
  /// Abstract types are handled too: the all-fields fragment of an interface
  /// (or converted union) projects through *every* implementor via
  /// `... on Impl { _all_fields_Impl }`, so the projected interface is just the
  /// declared interface and each projected implementor is its declared type.
  /// We therefore register the declared interface into [projectedInterfaces],
  /// wire its implementations, and blind-register every implementor.
  ///
  /// The [visited] guard bounds the cyclic object graph; the per-store
  /// containsKey check makes the walk idempotent across query elements (a type
  /// reachable from many roots is registered exactly once).
  void _registerAllFieldsBlind(GLTypeDefinition type, Set<String> visited) {
    if (!visited.add(type.token)) return;

    if (type is GLInterfaceDefinition) {
      if (!projectedInterfaces.containsKey(type.token)) {
        addToProjectedTypes(type, similarityCheck: false);
      }
      // Parent interfaces (interface implements interface) are not returned by
      // getTypesImplementing, which only scans concrete types, so follow them
      // explicitly to keep the projected-interface inheritance chain intact.
      _registerImplementedInterfacesBlind(type, visited);
      for (final impl in getTypesImplementing(type)) {
        type.addImplementation(impl);
        impl.addInterface(type);
        _registerAllFieldsBlind(impl, visited);
      }
      return;
    }

    if (!projectedTypes.containsKey(type.token)) {
      addToProjectedTypes(type, similarityCheck: false);
    }
    // A concrete type carries the interfaces it implements into the projected
    // output, so register (and wire) each one even though no field selection
    // reaches it. The slow path did this via _fillProjectedInterfaces.
    _registerImplementedInterfacesBlind(type, visited);
    for (final field in type.fields) {
      if (!typeRequiresProjection(field.type)) continue;
      final targetName = field.type.inlineType.token;
      // Unions are converted to interfaces before this pass, so both abstract
      // kinds resolve through the interfaces map.
      final abstract = interfaces[targetName];
      if (abstract != null) {
        _registerAllFieldsBlind(abstract, visited);
        continue;
      }
      final target = types[targetName];
      if (target != null) _registerAllFieldsBlind(target, visited);
    }
  }

  /// Blind-registers every interface that [type] implements (directly declared
  /// on the type or interface). The interface branch of [_registerAllFieldsBlind]
  /// registers the declared interface and wires its implementations.
  void _registerImplementedInterfacesBlind(
      GLTypeDefinition type, Set<String> visited) {
    for (final ifaceName in type.getInterfaceNames()) {
      final iface = interfaces[ifaceName];
      if (iface != null) _registerAllFieldsBlind(iface, visited);
    }
  }

  GLTypeDefinition createProjectedTypeForQuery(GLQueryElement element) {
    var type = element.returnType;
    var block = element.block!;
    var onType = getType(type.inlineType.tokenInfo);
    return createProjectedType(
        type: onType,
        projectionMap: block.projections,
        directives: element.getDirectives());
  }

  GLTypeDefinition addToProjectedTypes(GLTypeDefinition definition,
      {bool similarityCheck = true}) {
    var targetStore = definition is GLInterfaceDefinition
        ? projectedInterfaces
        : projectedTypes;
    if (definition.nameDeclared) {
      var type = targetStore[definition.token];
      if (type == null) {
        if (similarityCheck) {
          var similarDefinitions = findSimilarTo(definition);
          if (similarDefinitions.isNotEmpty) {
            similarDefinitions
                .where((element) => !element.nameDeclared)
                .forEach((e) {
              var currentDef = targetStore[e.token];
              if (currentDef != null) {
                currentDef.interfaceNames.forEach(definition.addInterfaceName);
                if (currentDef is GLInterfaceDefinition &&
                    definition is GLInterfaceDefinition) {
                  currentDef.implementations
                      .forEach(definition.addImplementation);
                }
              }
              targetStore[e.token] = definition;
            });
          }
        }

        targetStore[definition.token] = definition;
        definition.addOriginalToken(definition.token);
        return definition;
      } else {
        if (type.isSimilarTo(definition, this)) {
          type.addOriginalToken(definition.token);
          if (type is GLInterfaceDefinition &&
              definition is GLInterfaceDefinition) {
            definition.implementations.forEach(type.addImplementation);
          }
          return type;
        } else {
          var typeTokenInfo = type
              .getDirectiveByName(glTypeNameDirective)
              ?.getArgumentByName('name')
              ?.tokenInfo;
          throw ParseException(
              "You have names two object the same name '${definition.tokenInfo}' but have diffrent fields. ${definition.tokenInfo}_1.fields are: [${type.fields.map((f) => "${f.name}: ${serializer.serializeType(f.type)}").toList()}], ${definition.tokenInfo}_2.fields are: [${definition.fields.map((f) => "${f.name}: ${serializer.serializeType(f.type)}").toList()}]. Please consider renaming one of them",
              info: typeTokenInfo ?? type.tokenInfo);
        }
      }
    }

    if (similarityCheck) {
      var similarDefinitions = findSimilarTo(definition);

      if (similarDefinitions.isNotEmpty) {
        var first = similarDefinitions.first;
        first.addOriginalToken(definition.token);
        definition.interfaceNames.forEach(first.addInterfaceName);
        if (definition is GLInterfaceDefinition &&
            first is GLInterfaceDefinition) {
          definition.implementations.forEach(first.addImplementation);
        }
        // Union the incoming fields into the survivor. For a cyclic type the
        // two projections are "similar" but not identical: one is the
        // depth-truncated shape that dropped the cyclic edge, the other carries
        // it. Absorbing keeps the exhaustive field set on the single survivor,
        // so e.g. Book.author resolves to the full Author (with `book`), not a
        // truncated copy. For non-cyclic similars the field sets are identical,
        // so this is a no-op.
        for (final f in definition.fields) {
          first.addOrMergeField(f);
        }
        targetStore[first.token] = first;
        return first;
      }
    }

    String key = definition.token;
    targetStore[key] = definition;
    definition.addOriginalToken(key);
    final index = definition is GLInterfaceDefinition
        ? _interfaceHashIndex
        : _typeHashIndex;
    index.putIfAbsent(definition.getHash(this), () => []).add(definition);
    return targetStore[key]!;
  }

  List<GLTypeDefinition> findSimilarTo(GLTypeDefinition definition) {
    final index = definition is GLInterfaceDefinition
        ? _interfaceHashIndex
        : _typeHashIndex;
    final hash = definition.getHash(this);
    final candidates = index[hash];
    if (candidates == null) return [];
    return candidates.where((e) => e.isSimilarTo(definition, this)).toList();
  }

  String getUniqueName(Iterable<GLProjection> projections) {
    //@Todo check the inline fragment case.
    var keys = projections
        .map((e) => e.token)
        .where((t) => !t.endsWith("*"))
        .where((t) => t != GLParser.typename)
        .toSet()
        .toList();
    keys.sort();

    final pascalKeys =
        keys.map((k) => k.isEmpty ? k : k[0].toUpperCase() + k.substring(1));

    if (keys.length <= 3) {
      return pascalKeys.join();
    }

    final prefix = pascalKeys.take(3).join();
    final hash = _djb2(keys.join('_')).toRadixString(36);
    return '${prefix}_$hash';
  }

  bool _isExhaustiveProjection(List<GLField> result, GLTypeDefinition realType) {
    if (!generateAllFieldsFragments) return false;
    final resultFieldNames = result.map((f) => f.name.token).toSet();
    // A cyclic type has a single, depth-independent projected type: its
    // depth-truncated views drop the cyclic edge but are still "the" projection
    // of that type. Treat a missing field as covered when it's a cyclic edge, so
    // the truncated view earns the bare schema name (e.g. `Author`) and the
    // dedup pass folds it together with the full projection instead of minting a
    // separate `Author_IdName`.
    if (!realType.getSerializableFields(mode).every((f) =>
        resultFieldNames.contains(f.name.token) ||
        (typeRequiresProjection(f.type) &&
            isFieldCyclic(realType.token, f.type.inlineType.token)))) {
      return false;
    }
    return result.where((f) => typeRequiresProjection(f.type)).every((f) {
      final sub = projectedTypes[f.type.firstType.token]
               ?? projectedInterfaces[f.type.firstType.token];
      return sub != null;
    });
  }

  GeneratedTypeName _generateName(String originalName,
      Iterable<GLProjection> projections, List<GLDirectiveValue> directives) {
    String? name = getNameValueFromDirectives(directives);

    if (name != null) {
      return GeneratedTypeName(name, true);
    }

    name = "${originalName}_${getUniqueName(projections)}";
    String nameTemplate = name;

    int nameIndex = 0;
    if (name.endsWith("_*")) {
      nameTemplate = name.replaceFirst("_*", "");
      name = "${name.substring(0, name.length - 2)}_$nameIndex";
    }
    if (projectedTypes.containsKey(name)) {
      while (projectedTypes.containsKey(name)) {
        name = "${nameTemplate}_${++nameIndex}";
      }
    }
    return GeneratedTypeName(name ?? nameTemplate, false);
  }

  List<GLTypeDefinition> getProjectdeTypesImplementing(
      GLInterfaceDefinition def) {
    return projectedTypes.values.where((pt) {
      return pt.getInterfaceNames().contains(def.token);
    }).toList();
  }

  GLTypeDefinition createProjectedType({
    required GLTypeDefinition type,
    required Map<String, GLProjection> projectionMap,
    required List<GLDirectiveValue> directives,
  }) {
    // Fast path: the selection is just the generated all-fields spread, so the
    // projected type IS the declared type (its cyclic edges were already
    // relaxed to nullable by forceCyclicEdgesNullable). Register it and every
    // reachable type/interface directly, skipping the field rebuild + getHash +
    // findSimilarTo scan. Interfaces/unions are handled by _registerAllFieldsBlind
    // too: their all-fields fragment projects through every implementor, so the
    // projected interface is the declared interface and each implementor is its
    // declared type.
    if (_isSoleAllFieldsSpread(projectionMap)) {
      _registerAllFieldsBlind(type, <String>{});
      return type is GLInterfaceDefinition
          ? (projectedInterfaces[type.token] ?? type)
          : (projectedTypes[type.token] ?? type);
    }

    if (type is GLInterfaceDefinition) {
      var implementationTypes = getTypesImplementing(type);
      TypeWithInterface? result;
      final couples =  <TypeWithInterface>[];
      for (var it in implementationTypes) {
        var projections = _collectProjection(projectionMap, it.token);
        if (projections.isNotEmpty) {

          result = createProjectedTypeOnType(
            type: type,
            projectionMap: projectionMap,
            directives: type.getDirectives(),

            /// @TODO think about passing directives from inline fragments
            onTypeName: it.token,
          );
          couples.add(result);

        }
      }
      if (result != null) {
        final interfaces = couples.expand((e) => e.interfaces).toList();
        _updateInterfaceCommonFields(interfaces);
        _fillProjectedInterfaces(interfaces);
        var interface =  result.type.interfaces.first;
        return interface;
      }
    }

    var result = createProjectedTypeOnType(
      type: type,
      projectionMap: projectionMap,
      directives: directives,
      onTypeName: type.token,
    );
    if(result.interfaces.isNotEmpty ) {
       _updateInterfaceCommonFields(result.interfaces);
      _fillProjectedInterfaces(result.interfaces);
    }
    return result.type;
  }

  GLInterfaceDefinition _createNewInterface(GLInterfaceDefinition original) {
    return GLInterfaceDefinition(
      name: generateUuid().toToken(),
      nameDeclared: false,
      fields: [],
      directives: original.getDirectives(),
      interfaceNames: {},
      derivedFromType: original,
      extension: original.extension,
    );
  }

  GLTypeDefinition _createNewType(GeneratedTypeName name, List<GLField> fields,
      List<GLDirectiveValue> directives, GLTypeDefinition? realType) {
    return GLTypeDefinition(
      name: name.value.toToken(),
      nameDeclared: name.declared,
      fields: fields,
      interfaceNames: {},
      directives: directives,
      derivedFromType: realType,
      extension: false,
    );
  }

  TypeWithInterface createProjectedTypeOnType({
    required GLTypeDefinition type,
    required Map<String, GLProjection> projectionMap,
    required List<GLDirectiveValue> directives,
    required String onTypeName,
  }) {
    /// type might be an interface, we need to grab the real type from typesm map.
    var realType = type.token == onTypeName ? type : types[onTypeName]!;
    var src = [...realType.fields];

    var result = <GLField>[];
    var projections = _collectProjection(projectionMap, onTypeName);

    for (var field in src) {
      var projection = projections[field.name.token];
      if (projection != null) {
        final forceNull = typeRequiresProjection(field.type) &&
            isFieldCyclic(onTypeName, field.type.inlineType.token);
        result.add(_applyProjectionToField(
            field, projection, projection.getDirectives(), forceNull));
      }
    }
    final name = _isExhaustiveProjection(result, realType)
        ? GeneratedTypeName(onTypeName, false)
        : _generateName(onTypeName, projections.values, directives);
    var newType = _createNewType(name, result, directives, realType);
    final interfaceList = <GLInterfaceDefinition>[];
    for (var iface in realType.interfaces) {
      var interface = _createNewInterface(iface);
      interface.addImplementation(newType);
      interfaceList.add(interface);
    }

    var resultType = addToProjectedTypes(newType);
    if (!identical(resultType, newType)) {
      for (var iface in interfaceList) {
        iface.removeImplementation(newType.token);
        iface.addImplementation(resultType);
      }
    }
    return TypeWithInterface(type: resultType, interfaces: interfaceList);
  }

  /// Walks every operation's selection set (expanding fragment spreads and
  /// inline fragments) and, for every selected field that carries argument
  /// values referencing a `$variable`, ensures the owning operation declares
  /// that variable. This is what makes a field's arguments (e.g.
  /// `lastArticles(limit: Int!)`) turn into method parameters whenever the
  /// field is projected — whether via an explicit query, a fragment, or the
  /// auto-generated "all fields" projection.
  void propagateFieldArgumentVariables() {
    // The all-fields fragment graph is a single shared DAG (object fields point
    // at shared `_all_fields_<T>` spreads), referenced by every auto-generated
    // operation. The set of `$variable` arguments reachable from a given node —
    // a (selection-set, type) pair — is therefore invariant across operations,
    // so we compute it once and reuse it for each `def`. The cache is keyed
    // first by selection-set identity (Map uses identity equality) then by type
    // token. See [_argSpecsFor].
    final cache =
        <Map<String, GLProjection>, Map<String, Map<String, _GeneratedArgSpec>>>{};
    for (var def in queries.values) {
      for (var element in def.elements) {
        var block = element.block;
        if (block == null) continue;
        var rootType = getType(element.returnType.inlineType.tokenInfo);
        final specs =
            _argSpecsFor(rootType, _spreadTargetProjections(block), cache);
        for (final spec in specs.values) {
          _addGeneratedArgument(
              def, spec.varToken, spec.argDef, spec.field, spec.projection);
        }
      }
    }
  }

  /// Returns every distinct field-argument `$variable` reachable from the
  /// `(type, projectionMap)` node, de-duplicated by `varToken + full type
  /// signature` so the shared DAG never blows up into an exponential spec list.
  /// Memoized on [cache] so each shared node is walked exactly once across all
  /// operations. Distinct nullability variants of the same variable are kept as
  /// separate entries so the per-`def` merge in [_addGeneratedArgument] can pick
  /// the most-restrictive type and detect incompatible-base-type conflicts —
  /// preserving the behaviour of the previous per-operation walk.
  Map<String, _GeneratedArgSpec> _argSpecsFor(
      GLTypeDefinition type,
      Map<String, GLProjection> projectionMap,
      Map<Map<String, GLProjection>, Map<String, Map<String, _GeneratedArgSpec>>>
          cache) {
    final perType = cache.putIfAbsent(projectionMap, () => {});
    final cached = perType[type.token];
    if (cached != null) return cached;

    final result = <String, _GeneratedArgSpec>{};
    // Publish before recursing so any (pathological) re-entry returns the
    // in-progress map rather than looping. The all-fields DAG is acyclic by
    // construction (cyclic edges are inline-bounded), so this only guards.
    perType[type.token] = result;

    if (type is GLInterfaceDefinition) {
      for (var impl in getTypesImplementing(type)) {
        _mergeArgSpecs(result, _argSpecsFor(impl, projectionMap, cache));
      }
      return result;
    }

    var projections = _collectProjection(projectionMap, type.token);
    for (var field in type.fields) {
      var projection = projections[field.name.token];
      if (projection == null) continue;

      for (var argValue in projection.arguments) {
        var value = "${argValue.value}";
        if (!value.startsWith("\$")) continue;
        var argDef = field.getArgumentByName(argValue.tokenInfo.token);
        if (argDef == null) continue;
        final key = '$value ${_argTypeSignature(argDef.type)}';
        result.putIfAbsent(
            key, () => _GeneratedArgSpec(value, argDef, field, projection));
      }

      if (projection.block != null && typeRequiresProjection(field.type)) {
        var subType = getType(field.type.inlineType.tokenInfo);
        _mergeArgSpecs(result,
            _argSpecsFor(subType, _spreadTargetProjections(projection.block!), cache));
      }
    }
    return result;
  }

  /// When [block] is a single all-fields fragment spread, returns the spread
  /// fragment's own `block.projections` — a single shared map instance reused by
  /// every field that points at the same type. Returning the shared map (rather
  /// than the per-field wrapper that `createAllFieldBlock` allocates fresh each
  /// time) is what lets the identity-keyed `visited` dedup in
  /// [_collectFieldArgumentVariables] actually fire, so the shared fragment DAG
  /// is walked once per type instead of re-expanded as a tree.
  ///
  /// An implicit `__typename` is ignored when deciding "single spread": it is
  /// auto-injected into interface/union (inline-fragment) blocks for `fromJson`
  /// dispatch, so the spread is not necessarily the map's only entry — mirroring
  /// [_isSoleAllFieldsSpread]. Falls back to the block's own projections for
  /// anything that isn't a sole fragment spread (e.g. inline-expanded back-edge
  /// blocks).
  Map<String, GLProjection> _spreadTargetProjections(
      GLFragmentBlockDefinition block) {
    final projections = block.projections;
    GLProjection? spread;
    for (final entry in projections.entries) {
      if (entry.key == GLParser.typename) continue;
      if (spread != null) return projections; // more than one real selection
      spread = entry.value;
    }
    if (spread != null && spread.isFragmentReference) {
      final frag = getFragmentByName(spread.fragmentName!);
      if (frag != null) return frag.block.projections;
    }
    return projections;
  }

  /// Returns the `$variable` tokens (e.g. `$limit`, `$authorId`) that a
  /// single query element actually references: its own root-field
  /// arguments plus any field-argument variables reachable through its
  /// selection set (including through fragments and inline fragments).
  ///
  /// Used to scope each divided/partial query to only the variables it
  /// needs, instead of the full set of variables declared on the operation.
  Set<String> elementArgumentVariables(GLQueryElement element) {
    var result = <String>{};
    for (var argValue in element.arguments) {
      var value = "${argValue.value}";
      if (value.startsWith("\$")) {
        result.add(value);
      }
    }
    var block = element.block;
    if (block != null) {
      var rootType = getType(element.returnType.inlineType.tokenInfo);
      _collectFieldArgumentVariableTokens(
          rootType, block.projections, result, <String>{});
    }
    return result;
  }

  void _collectFieldArgumentVariableTokens(
      GLTypeDefinition type,
      Map<String, GLProjection> projectionMap,
      Set<String> result,
      Set<String> visited) {
    // Visited guard on (type, projection-block identity). `projectionMap` is a
    // stable AST node, so the set of `$variable` tokens reachable from a given
    // (type, block) pair is fixed. Because `result` accumulates globally, once
    // a node has been walked its tokens are already collected — re-walking adds
    // nothing, so skipping a revisit is safe (no per-node result to cache, so a
    // visited set suffices; full memoization would be redundant here). This
    // turns what was an exponential walk of the expanded selection DAG (and an
    // infinite walk on cyclic types like GitLab's Project → … → Project) into a
    // linear one, without changing the result.
    final visitKey = '${type.token}#${identityHashCode(projectionMap)}';
    if (!visited.add(visitKey)) return;

    if (type is GLInterfaceDefinition) {
      for (var impl in getTypesImplementing(type)) {
        _collectFieldArgumentVariableTokens(
            impl, projectionMap, result, visited);
      }
      return;
    }

    var projections = _collectProjection(projectionMap, type.token);
    for (var field in type.fields) {
      var projection = projections[field.name.token];
      if (projection == null) continue;

      for (var argValue in projection.arguments) {
        var value = "${argValue.value}";
        if (value.startsWith("\$")) {
          result.add(value);
        }
      }

      if (projection.block != null && typeRequiresProjection(field.type)) {
        var subType = getType(field.type.inlineType.tokenInfo);
        _collectFieldArgumentVariableTokens(
            subType, projection.block!.projections, result, visited);
      }
    }
  }

  /// Merges [from] into [into], keeping the first-seen spec per key so the
  /// flattened insertion order matches a depth-first walk's first-seen order
  /// (which determines generated argument declaration order).
  void _mergeArgSpecs(Map<String, _GeneratedArgSpec> into,
      Map<String, _GeneratedArgSpec> from) {
    for (final entry in from.entries) {
      into.putIfAbsent(entry.key, () => entry.value);
    }
  }

  /// Stable signature of a type including list nesting and nullability — used to
  /// key [_argSpecsFor] so two occurrences of the same `$variable` that differ
  /// only in nullability are kept distinct (and later merged to most-restrictive
  /// per `def`), while exact duplicates collapse.
  String _argTypeSignature(GLType t) {
    if (t is GLListType) {
      return '[${_argTypeSignature(t.type)}]${t.nullable ? '?' : '!'}';
    }
    return '${t.token}${t.nullable ? '?' : '!'}';
  }

  void _addGeneratedArgument(GLQueryDefinition def, String varToken,
      GLArgumentDefinition argDef, GLField field, GLProjection projection) {
    final existing = def.getArgumentByName(varToken);
    if (existing != null) {
      if (existing.type == argDef.type) return;
      if (!_sameBaseType(existing.type, argDef.type)) {
        throw ParseException(
            "Variable $varToken is used for arguments of incompatible types "
            "(${existing.type.token} vs ${argDef.type.token}). Use a differently named "
            "variable to disambiguate, e.g. ${field.name}(${argDef.tokenInfo}: \$myVar)",
            info: projection.tokenInfo);
      }
      // same base type, different nullability — upgrade to most restrictive
      final merged = _mostRestrictiveType(existing.type, argDef.type);
      final keptDefault = existing.defaultValue ?? argDef.defaultValue;
      // A null default is incompatible with a non-nullable type — drop it so
      // we don't emit e.g. `String x = null` (a Dart compile error).
      final defaultValue = (!merged.nullable && keptDefault?.value == null)
          ? null
          : keptDefault;
      def.setArgument(GLArgumentDefinition(
          varToken.toToken(), merged, [],
          defaultValue: defaultValue, isDeclared: false));
      return;
    }
    def.setArgument(GLArgumentDefinition(
        varToken.toToken(), argDef.type, [],
        defaultValue: argDef.defaultValue, isDeclared: false));
  }

  bool _sameBaseType(GLType a, GLType b) {
    if (a is GLListType && b is GLListType) return _sameBaseType(a.type, b.type);
    if (a is GLListType || b is GLListType) return false;
    return a.token == b.token;
  }

  GLType _mostRestrictiveType(GLType a, GLType b) {
    if (a is GLListType && b is GLListType) {
      return GLListType(_mostRestrictiveType(a.type, b.type), a.nullable && b.nullable);
    }
    return GLType(a.tokenInfo, a.nullable && b.nullable);
  }

  Map<String, GLProjection> _collectProjection(
      Map<String, GLProjection> projections, String onTypeName) {
    var result = <String, GLProjection>{};
    projections.forEach((k, v) {
      if (v.isFragmentReference) {
        var fragment = getFragmentByName(v.fragmentName!)!;
        var r = _collectProjection(fragment.block.projections, onTypeName);
        result.addAll(r);
      } else if (v is GLInlineFragmentsProjection) {
        v.inlineFragments
            .where((inline) => inline.onTypeName.token == onTypeName)
            .forEach((inline) {
          var r = _collectProjection(inline.block.projections, onTypeName);
          result.addAll(r);
        });
      } else {
        result[k] = v;
      }
    });
    return result;
  }

  GLField _applyProjectionToField(GLField field, GLProjection projection,
      [List<GLDirectiveValue> fieldDirectives = const [],
      bool forceNullable = false]) {
    final TokenInfo fieldName = projection.alias ?? field.name;
    var block = projection.block;

    if (block != null) {
      //we should create another type here ...
      var generatedType = createProjectedType(
        type: getType(field.type.tokenInfo),
        projectionMap: block.projections,
        directives: fieldDirectives,
      );
      var fieldInlineType =
          GLType(generatedType.tokenInfo, field.type.nullable);
      var fieldType = _createTypeFrom(field.type, fieldInlineType);
      if (forceNullable) fieldType = GLType.makeNullable(fieldType);

      return GLField(
        name: fieldName,
        type: fieldType,
        arguments: field.arguments,
        directives: projection.getDirectives(),
      );
    }

    return GLField(
      name: fieldName,
      type: _createTypeFrom(field.type, field.type),
      arguments: field.arguments,
      directives: projection.getDirectives(),
    );
  }

  GLType _createTypeFrom(GLType orig, GLType inline) {
    if (orig is GLListType) {
      return GLListType(_createTypeFrom(orig.type, inline), orig.nullable);
    }
    return GLType(inline.tokenInfo, orig.inlineType.nullable);
  }

  void fixProjectedInterfaceConflicts() {
    var ifaceList = projectedInterfaces.entries.toList();

    for (var entry in ifaceList) {
      var iface = entry.value;

      var groups = <String, List<GLTypeDefinition>>{};
      for (var impl in iface.implementations) {
        var key = impl.derivedFromType?.token ?? impl.token;
        groups.putIfAbsent(key, () => []).add(impl);
      }

      for (var impls in groups.values) {
        if (impls.length <= 1) continue;

        for (var impl in impls.skip(1)) {
          iface.removeImplementation(impl.token);
          impl.unlinkInterface(iface);

          var newName = _uniqueProjectedInterfaceName(iface.token);
          var newIface = GLInterfaceDefinition(
            name: iface.tokenInfo.ofNewName(newName),
            nameDeclared: false,
            fields: List.from(iface.fields),
            directives: iface.getDirectives(),
            interfaceNames: {},
            extension: false,
            derivedFromType: iface.derivedFromType,
          );

          impl.addInterface(newIface);
          projectedInterfaces[newName] = newIface;
        }
      }
    }
  }

  String _uniqueProjectedInterfaceName(String baseName) {
    var i = 1;
    var name = '${baseName}_$i';
    while (projectedInterfaces.containsKey(name) || projectedTypes.containsKey(name)) {
      name = '${baseName}_${++i}';
    }
    return name;
  }
}

class GeneratedTypeName {
  // the generated name value
  final String value;
  //true if the name has been declared using @glTypeName directive
  final bool declared;

  GeneratedTypeName(this.value, this.declared);
}


class TypeWithInterface {
  final List<GLInterfaceDefinition> interfaces;
  final GLTypeDefinition type;

  TypeWithInterface({required this.type, required this.interfaces});
}
