import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_query_element.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/gl_expand_grammar_extension.dart';

extension GLGrammarFragmentExtension on GLParser {
  void fillQueryElementArgumentTypes(
      GLQueryElement element, GLQueryDefinition query) {
    for (var arg in element.arguments) {
      var list = query.arguments.where((a) => a.token == arg.value).toList();
      if (list.isEmpty) {
        throw ParseException(
            "Could not find argument ${arg.value} on query ${query.tokenInfo}",
            info: arg.tokenInfo);
      }
      arg.type = list.first.type;
    }
  }

  void fillQueryElementsReturnType() {
    queries.forEach((name, queryDefinition) {
      for (var element in queryDefinition.elements) {
        element.returnType = getTypeFromFieldName(element.token,
            schema.getByQueryType(queryDefinition.type), element.tokenInfo);
        fillQueryElementArgumentTypes(element, queryDefinition);
      }
    });
  }

  GLType getFieldType(TokenInfo fieldNameToken, String typeName) {
    final fieldName = fieldNameToken.token;
    final onType = getType(fieldNameToken.ofNewName(typeName));
    final field = onType.getFieldByName(fieldName);
    if (field == null) {
      if (fieldName == GLParser.typename) return GLType("String".toToken(), false);
      throw ParseException(
          "Could not find field '$fieldName' on type '$typeName'",
          info: fieldNameToken);
    }
    return field.type;
  }

  void updateFragmentAllTypesDependencies() {
    fragments.forEach((key, fragment) {
      fragment.block.projections.values
          .where((projection) => projection.block == null)
          .forEach((projection) {
        handleFragmentDepenecy(fragment, projection);
      });
    });
  }

  void handleFragmentDepenecy(
      GLFragmentDefinitionBase fragment, GLProjection projection) {
    if (projection is GLInlineFragmentsProjection) {
      for (var inlineFrag in projection.inlineFragments) {
        inlineFrag.block.projections.forEach((k, proj) {
          if (projection.block == null) {
            handleFragmentDepenecy(fragment, proj);
          }
        });
      }
    } else if (projection.isFragmentReference) {
      var fragmentRef =
          getFragment(projection.targetToken, projection.tokenInfo);

      fragment.addDependecy(fragmentRef);
    } else {
      var type = getType(fragment.onTypeName);
      var field = type.findFieldByName(projection.token, this);
      if (types.containsKey(field.type.token)) {
        fragment.addDependecy(fragments[field.type.token]!);
      }
    }
  }

  GLType getTypeFromFieldName(
      String fieldName, String typeName, TokenInfo fieldToken) {
    final type = getType(fieldToken.ofNewName(typeName));
    final field = type.getFieldByName(fieldName);
    if (field == null) {
      throw ParseException(
          "$typeName does not declare a field with name $fieldName",
          info: type.tokenInfo);
    }
    return field.type;
  }

  void updateFragmentDependencies() {
    fragments.forEach((key, value) {
      value.updateDepencies(fragments);
    });
  }

  /// Marks every fragment that is referenced (directly or transitively) by at
  /// least one query, mutation, or subscription. Only fragments with
  /// `used == true` are emitted into the generated client fragment map.
  void markUsedFragments() {
    // Reset all fragments to unused first.
    for (final frag in fragments.values) {
      frag.used = false;
    }
    // Iterate every operation — each op.fragments() returns the full
    // transitive closure via the dependency graph already populated by
    // updateFragmentDependencies + updateFragmentAllTypesDependencies.
    for (final op in queries.values) {
      for (final frag in op.fragments(this)) {
        frag.used = true;
      }
    }
  }

  /// Returns only the fragments that are referenced by at least one operation
  /// (query, mutation, or subscription). Call [markUsedFragments] first.
  Iterable<GLFragmentDefinitionBase> get usedFragments =>
      fragments.values.where((f) => f.used);

  /// Names of used fragments whose serialized body exceeds [maxFragmentBodySize].
  /// Populated by [GLClientSerializer] on first use and cached here.
  Set<String> get oversizedFragmentNames => oversizedFragmentNamesCache ?? const {};


  void fillTypedFragments() {
    fragments.forEach((key, fragment) {
      checkIfDefined(fragment.onTypeName);
      typedFragments[key] =
          GLTypedFragment(fragment, getType(fragment.onTypeName));
    });
  }

  /// Generates `(arg: $arg, ...)` argument values referencing same-named
  /// variables for every argument the field declares, so that selecting the
  /// field always carries its required arguments along.
  List<GLArgumentValue> _argumentValuesForField(GLField field) {
    final fieldName = field.name.token;
    return field.arguments.map((a) {
      final argName = a.tokenInfo.token;
      // Base variable token is `$<field><Arg>` — the field name keeps each
      // field's argument independent (so unrelated `users(filter:)` and
      // `posts(filter:)` don't share one value). Only when the *same*
      // field+arg name resolves to incompatible base types across the schema
      // (e.g. GitLab's Commit.associatedPullRequests(orderBy: PullRequestOrder)
      // vs Ref.associatedPullRequests(orderBy: IssueOrder)) do we escalate by
      // appending the base type, making each variant unique. Unambiguous
      // arguments keep the clean name and still merge nullability-only variants.
      var token = '${fieldName}${argName.firstUp}';
      if (ambiguousArgKeys.contains('$fieldName|$argName')) {
        token = '$token${a.type.firstType.token.firstUp}';
      }
      return GLArgumentValue(a.tokenInfo, '\$$token');
    }).toList();
  }

  /// Signature for an argument's base type that ignores nullability but
  /// distinguishes list nesting and inner type — matching the `_sameBaseType`
  /// notion used when merging generated query variables. Two arguments with the
  /// same signature can safely share a variable; differing signatures cannot.
  String _baseTypeSignature(GLType type) {
    var depth = 0;
    var t = type;
    while (t is GLListType) {
      depth++;
      t = t.type;
    }
    return '$depth:${t.token}';
  }

  /// `<fieldName>|<argName>` keys whose argument resolves to more than one
  /// incompatible base type across all type/interface fields. Memoized on the
  /// parser. See `_argumentValuesForField`.
  Set<String> get ambiguousArgKeys => ambiguousArgKeysCache.getOrCompute(() {
        final signaturesByKey = <String, Set<String>>{};
        void scan(Iterable<GLTypeDefinition> defs) {
          for (final type in defs) {
            for (final field in type.fields) {
              for (final arg in field.arguments) {
                final key = '${field.name.token}|${arg.tokenInfo.token}';
                (signaturesByKey[key] ??= <String>{})
                    .add(_baseTypeSignature(arg.type));
              }
            }
          }
        }

        scan(types.values);
        scan(interfaces.values);

        return <String>{
          for (final entry in signaturesByKey.entries)
            if (entry.value.length > 1) entry.key,
        };
      });

  GLFragmentDefinition createAllFieldsFragment(GLTypeDefinition typeDefinition) {
    var key = typeDefinition.token;
    var allFieldsKey = GLGrammarExtension.allFieldsFragmentName(key);

    if (typeDefinition is GLInterfaceDefinition) {
      var projection = _createProjectionForInterface(typeDefinition);
      var block = GLFragmentBlockDefinition([projection])..validated = true;
      return GLFragmentDefinition(
          allFieldsKey.toToken(), typeDefinition.tokenInfo, block, []);
    }

    final queryTypeNames =
        GLQueryType.values.map((t) => schema.getByQueryType(t)).toSet();

    final projections = typeDefinition.getSerializableFields(mode).map((field) {
      if (typeRequiresProjection(field.type)) {
        final fieldTypeName = field.type.inlineType.token;
        // Query/Mutation/Subscription root types are excluded from fragment
        // generation, so any field pointing to them must also be skipped.
        if (queryTypeNames.contains(fieldTypeName)) return null;
        // Break the cycle's back-edges by inline-bounding them with the target
        // type's @glExpand depth. Every other cyclic edge keeps spreading its
        // `_all_fields_<T>` fragment, so a forward chain stays intact and
        // interface/union edges keep their abstract fragment (and implementor
        // projections) reachable. Back-edges come from the order-independent
        // feedback-set pass (isBackEdgeField), not a stack.
        if (isBackEdgeField(typeDefinition.token, field.name.token)) {
          // The back-edge target is usually concrete, but an abstract-only cycle
          // (closed solely through an interface/union edge) breaks the abstract
          // edge itself — inline-expand it through its concrete members.
          final isConcreteTarget = types.containsKey(fieldTypeName);
          final depth = isConcreteTarget
              ? _getExpandDepth(types[fieldTypeName]!)
              : _getExpandDepth(typeDefinition);
          // depth 0 → skip the cyclic field entirely (no block, no field).
          if (depth <= 0) return null;
          // depth-1: so depth=1 gives scalars only, depth=2 gives one sub-level, etc.
          final block = isConcreteTarget
              ? _createInlineExpandBlock(fieldTypeName, depth - 1)
              : _inlineExpandTarget(fieldTypeName, depth - 1, <String>{});
          if (block == null) return null;
          return GLProjection(
            fragmentName: null,
            token: field.name,
            alias: null,
            block: block,
            directives: [],
            arguments: _argumentValuesForField(field),
          );
        }
      }
      return GLProjection(
        fragmentName: null,
        token: field.name,
        alias: null,
        block: createAllFieldBlock(field),
        directives: [],
        arguments: _argumentValuesForField(field),
      );
    }).whereType<GLProjection>().toList();

    return GLFragmentDefinition(
        allFieldsKey.toToken(),
        typeDefinition.tokenInfo,
        GLFragmentBlockDefinition(projections)..validated = true,
        []);
  }

  void createAllFieldsFragments() {
    final allTypes = {...types, ...interfaces};
    final queryTypeNames =
        GLQueryType.values.map((t) => schema.getByQueryType(t)).toSet();

    // Cycle breaking is driven by the static SCC pass (isFieldCyclic), so each
    // type's fragment is self-contained and can be generated in any order — no
    // dependency DFS or in-progress stack is required.
    allTypes.forEach((key, typeDef) {
      if (queryTypeNames.contains(key)) return;
      if (typeDef.getDirectiveByName(glInternal) != null) return;
      addFragmentDefinition(createAllFieldsFragment(typeDef));
    });
  }

  int _getExpandDepth(GLTypeDefinition typeDef) {
    final directive = typeDef.getDirectiveByName(glExpand);
    if (directive == null) return defaultExpandDepth;
    final value = directive.getArgValue(glExpandDepth);
    return value is int ? value : defaultExpandDepth;
  }

  /// Recursively inline-expands [typeName]'s fields up to [remainingDepth]
  /// cyclic levels. Never emits a fragment spread for a cyclic edge — those are
  /// inlined to keep the fragment-reference graph acyclic. Interface/union
  /// fields encountered here are inlined as inline-fragments over their concrete
  /// members (see [_inlineExpandTarget]).
  ///
  /// Cyclic edges (per the SCC pass, [isFieldCyclic]) decrement [remainingDepth]
  /// and are dropped at 0. [visitedOnPath] tracks types on the current call
  /// stack to bound long non-cyclic chains that eventually loop back to a cyclic
  /// type (e.g. Link1→Link2→…→LinkN→Root where the Links are not cyclic, so
  /// remainingDepth never decrements along the chain).
  GLFragmentBlockDefinition? _createInlineExpandBlock(
      String typeName, int remainingDepth,
      [Set<String>? visitedOnPath]) {
    final path = visitedOnPath ?? <String>{};

    final isCyclicType = cyclicTypeNames.contains(typeName);

    // Non-cyclic cache hit: return the previously computed block directly.
    // fragmentBlockCache is shared across all createAllFieldsFragments calls.
    if (!isCyclicType && fragmentBlockCache.containsKey(typeName)) {
      return fragmentBlockCache[typeName];
    }

    // Skip non-cyclic types already on the path to prevent unbounded recursion
    // through non-cyclic chains. Cyclic types are bounded by remainingDepth
    // instead, so the path check must not block them — otherwise depth>1
    // expansions terminate early.
    if (path.contains(typeName) && !isCyclicType) return null;

    final typeDef = types[typeName];
    if (typeDef == null) return null;

    path.add(typeName);

    final projections = typeDef.getSerializableFields(mode).map((field) {
      if (!typeRequiresProjection(field.type)) {
        return GLProjection(
          fragmentName: null,
          token: field.name,
          alias: null,
          block: null,
          directives: [],
          arguments: _argumentValuesForField(field),
        );
      }

      final fieldTypeName = field.type.inlineType.token;
      final isCyclic = isFieldCyclic(typeName, fieldTypeName);

      if (isCyclic && remainingDepth <= 0) return null;

      final nextDepth = isCyclic ? remainingDepth - 1 : remainingDepth;
      final block = _inlineExpandTarget(fieldTypeName, nextDepth, path);
      // If expansion returned null (path-skip or unknown type), omit the field
      // entirely — a null block on an object-type field is invalid.
      if (block == null) return null;
      return GLProjection(
        fragmentName: null,
        token: field.name,
        alias: null,
        block: block,
        directives: [],
        arguments: _argumentValuesForField(field),
      );
    }).whereType<GLProjection>().toList();

    path.remove(typeName);

    final result = GLFragmentBlockDefinition(projections);

    // Cache the result for non-cyclic types so all subsequent calls reuse
    // the same block object instead of re-expanding the same subgraph.
    if (!isCyclicType) fragmentBlockCache[typeName] = result;

    return result;
  }

  /// Expands a field's [targetName] during inline expansion. Concrete types
  /// recurse into [_createInlineExpandBlock]; interface/union targets become
  /// inline-fragments over their concrete members, each inlined (never spread)
  /// so the fragment-reference graph stays acyclic at any depth.
  GLFragmentBlockDefinition? _inlineExpandTarget(
      String targetName, int remainingDepth, Set<String> path) {
    if (types.containsKey(targetName)) {
      return _createInlineExpandBlock(targetName, remainingDepth, path);
    }
    final members = _concreteMembers(targetName);
    if (members.isEmpty) return null;
    final inlineFrags = <GLInlineFragmentDefinition>[];
    for (final member in members) {
      final block = _createInlineExpandBlock(member.token, remainingDepth, path);
      if (block == null) continue;
      final inline = GLInlineFragmentDefinition(member.tokenInfo, block, []);
      addFragmentDefinition(inline);
      inlineFrags.add(inline);
    }
    if (inlineFrags.isEmpty) return null;
    return GLFragmentBlockDefinition(
        [GLInlineFragmentsProjection(inlineFragments: inlineFrags)]);
  }

  /// Concrete member type definitions of an interface (its implementors) or a
  /// union (its members). Empty for anything else.
  List<GLTypeDefinition> _concreteMembers(String targetName) {
    if (interfaces.containsKey(targetName)) {
      return getTypesImplementing(interfaces[targetName]!);
    }
    if (unions.containsKey(targetName)) {
      return unions[targetName]!
          .typeNames
          .map((t) => types[t.token])
          .whereType<GLTypeDefinition>()
          .toList();
    }
    return [];
  }

  GLFragmentBlockDefinition? createAllFieldBlock(GLField field) {
    if (!typeRequiresProjection(field.type)) {
      return null;
    }
    return GLFragmentBlockDefinition([
      GLProjection(
        fragmentName: GLGrammarExtension.allFieldsFragmentName(field.type.inlineType.token),
        token: field.type.inlineType.tokenInfo
            .ofNewName(GLGrammarExtension.allFieldsFragmentName(field.type.inlineType.token)),
        alias: null,
        block: null,
        directives: [],
        allFieldsSpread: true,
      )
    ]);
  }

  generateQueryDefinitions() {
    var queryDeclarations = types[schema.getByQueryType(GLQueryType.query)];
    if (queryDeclarations != null) {
      generateQueries(queryDeclarations, GLQueryType.query);
    }

    var mutationDeclarations =
        types[schema.getByQueryType(GLQueryType.mutation)];
    if (mutationDeclarations != null) {
      generateQueries(mutationDeclarations, GLQueryType.mutation);
    }

    var subscriptionDeclarations =
        types[schema.getByQueryType(GLQueryType.subscription)];
    if (subscriptionDeclarations != null) {
      generateQueries(subscriptionDeclarations, GLQueryType.subscription);
    }
  }

  void generateQueries(GLTypeDefinition def, GLQueryType queryType) {
    final filter = autoGenerateQueriesFor?[queryType];
    if (filter != null) {
      final available = def.fields.map((f) => f.name.token).toSet();
      final missing = filter.where((name) => !available.contains(name)).toList();
      if (missing.isNotEmpty) {
        const keyByType = {
          GLQueryType.query: 'queries',
          GLQueryType.mutation: 'mutations',
          GLQueryType.subscription: 'subscriptions',
        };
        final key = keyByType[queryType]!;
        throw ParseException(
          'autoGenerateQueriesFor.$key lists unknown operation(s): ${missing.join(', ')}',
        );
      }
      final filterSet = filter.toSet();
      for (var field in def.fields) {
        if (filterSet.contains(field.name.token)) _generateForField(field, queryType);
      }
    } else {
      for (var field in def.fields) {
        _generateForField(field, queryType);
      }
    }
  }

  String generateAllFieldFragment(GLType type) {
    // check if type is an interface
    if (interfaces.containsKey(type.token)) {
      var iface = interfaces[type.token]!;
      GLProjection projection = _createProjectionForInterface(iface);

      var block = GLFragmentBlockDefinition([projection]);
      var frag = GLInlineFragmentDefinition(iface.tokenInfo, block, []);
      addFragmentDefinition(frag);
      return frag.token;
    }
    final fragName = "${allFields}_${type.tokenInfo.token}";
    getFragment(fragName, type.tokenInfo);
    return fragName;
  }

  void _generateForField(GLField field, GLQueryType queryType) {
    GLFragmentBlockDefinition? block;
    if (typeRequiresProjection(field.type)) {
      final fieldTypeName = field.type.inlineType.token;
      // Skip fields whose type is a query root (Query/Mutation/Subscription) —
      // those types have no all-fields fragment because they are excluded from
      // fragment generation. The github schema has `relay: Query!` as a Relay
      // workaround; attempting to generate a fragment for it would fail.
      final queryTypeNames =
          GLQueryType.values.map((t) => schema.getByQueryType(t)).toSet();
      if (queryTypeNames.contains(fieldTypeName)) return;

      final fragName = generateAllFieldFragment(field.type);
      block = GLFragmentBlockDefinition([
        GLProjection(
            fragmentName: fragName,
            token: fragName.toToken(),
            alias: null,
            block: null,
            directives: [],
            allFieldsSpread: true)
      ]);
    }

    var argValues = field.arguments.map((arg) {
      return GLArgumentValue(arg.tokenInfo, "\$${arg.tokenInfo}");
    }).toList();
    const inheritedDirectives = [glCache, glNoCache, glCacheInvalidate, glCaptureErrors];
    var directives = field
        .getDirectives()
        .where((e) => inheritedDirectives.contains(e.token))
        .toList();
    var queryElement = GLQueryElement(
        field.name, directives, block, argValues, defaultAlias?.toToken());
    final def = GLQueryDefinition(
        field.name,
        [],
        field.arguments
            .map((e) => GLArgumentDefinition(
                "\$${e.tokenInfo}".toToken(), e.type, [],
                defaultValue: e.defaultValue))
            .toList(),
        [queryElement],
        queryType)
      ..isAutoGenerated = true;
    addQueryDefinition(def);
  }

  GLProjection _createProjectionForInterface(GLInterfaceDefinition interface) {
    var implementors = getTypesImplementing(interface);
    // Query root types (Query/Mutation/Subscription) are excluded from fragment
    // generation (e.g. GitLab's `type Query implements Node`). Skip them here
    // so no _all_fields_Query spread is emitted into the interface fragment.
    final queryTypeNames =
        GLQueryType.values.map((t) => schema.getByQueryType(t)).toSet();
    var inlineFrags = <GLInlineFragmentDefinition>[];

    implementors
        .where((t) => !queryTypeNames.contains(t.token))
        .map((t) {
      var token = t.tokenInfo.ofNewName("${allFields}_${t.token}");
      var inlineDef = GLInlineFragmentDefinition(
          t.tokenInfo,
          GLFragmentBlockDefinition([
            GLProjection(
                fragmentName: token.token,
                token: token,
                alias: null,
                block: null,
                directives: [])
          ]),
          []);
      inlineFrags.add(inlineDef);
      addFragmentDefinition(inlineDef);
    }).toList();

    return GLInlineFragmentsProjection(inlineFragments: inlineFrags);
  }
}
