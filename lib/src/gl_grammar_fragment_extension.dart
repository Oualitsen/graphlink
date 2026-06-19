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
      return GLArgumentValue(a.tokenInfo, '\$${fieldName}${argName.firstUp}');
    }).toList();
  }

  GLFragmentDefinition createAllFieldsFragment(
      GLTypeDefinition typeDefinition, Set<String> inProgress) {
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
        if (inProgress.contains(fieldTypeName)) {
          // Cyclic field — inline-expand using the back-referenced type's depth.
          final cyclicType = types[fieldTypeName] ?? interfaces[fieldTypeName];
          final depth = cyclicType != null ? _getExpandDepth(cyclicType) : defaultExpandDepth;
          // depth 0 → skip the cyclic field entirely (no block, no field).
          if (depth <= 0) return null;
          return GLProjection(
            fragmentName: null,
            token: field.name,
            alias: null,
            // depth-1: so depth=1 gives scalars only, depth=2 gives one sub-level, etc.
            block: _createInlineExpandBlock(fieldTypeName, depth - 1, inProgress),
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

    final Set<String> done = {};
    final Set<String> inProgress = {};
    int count = 0;

    void generate(String key) {
      if (done.contains(key) || inProgress.contains(key)) return;
      final typeDef = allTypes[key]!;
      inProgress.add(key);

      // Ensure all non-cyclic dependencies are generated first (DFS).
      for (final field in typeDef.getSerializableFields(mode)) {
        if (typeRequiresProjection(field.type)) {
          final depKey = field.type.inlineType.token;
          if (allTypes.containsKey(depKey) &&
              !queryTypeNames.contains(depKey) &&
              allTypes[depKey]!.getDirectiveByName(glInternal) == null) {
            generate(depKey);
          }
        }
      }

      addFragmentDefinition(createAllFieldsFragment(typeDef, inProgress));
      inProgress.remove(key);
      done.add(key);
      count++;
    }

    allTypes.forEach((key, typeDef) {
      if (!queryTypeNames.contains(key) &&
          typeDef.getDirectiveByName(glInternal) == null) {
        generate(key);
      }
    });
  }

  int _getExpandDepth(GLTypeDefinition typeDef) {
    final directive = typeDef.getDirectiveByName(glExpand);
    if (directive == null) return defaultExpandDepth;
    final value = directive.getArgValue(glExpandDepth);
    return value is int ? value : defaultExpandDepth;
  }

  /// Recursively inline-expands [typeName]'s fields up to [remainingDepth] levels.
  /// Never emits fragment spreads — everything is inlined to avoid introducing
  /// new fragment-level cycles.
  ///
  /// [visitedOnPath] tracks types on the current call stack to prevent stack
  /// overflows from long non-cyclic chains that eventually loop back to a
  /// cyclic type (e.g. Link1→Link2→...→LinkN→Root where Root is in cycleTypes
  /// but the Links are not, so remainingDepth never decrements along the chain).
  GLFragmentBlockDefinition? _createInlineExpandBlock(
      String typeName, int remainingDepth, Set<String> cycleTypes,
      [Set<String>? visitedOnPath]) {
    final path = visitedOnPath ?? <String>{};

    final isCyclicType = cycleTypes.contains(typeName);

    // Non-cyclic cache hit: return the previously computed block directly.
    // fragmentBlockCache is shared across all createAllFieldsFragments calls.
    if (!isCyclicType && fragmentBlockCache.containsKey(typeName)) {
      return fragmentBlockCache[typeName];
    }

    // Skip non-cyclic types already on the path to prevent unbounded recursion
    // through non-cyclic chains (e.g. Link1→Link2→...→LinkN). Cyclic types
    // (those in cycleTypes) are bounded by remainingDepth instead, so the path
    // check must not block them — otherwise depth>1 expansions terminate early.
    if (path.contains(typeName) && !isCyclicType) return null;

    final typeDef = types[typeName] ?? interfaces[typeName];
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
      final isCyclic = cycleTypes.contains(fieldTypeName);

      if (isCyclic && remainingDepth <= 0) return null;

      final nextDepth = isCyclic ? remainingDepth - 1 : remainingDepth;
      final block = _createInlineExpandBlock(fieldTypeName, nextDepth, cycleTypes, path);
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
    for (var field in def.fields) {
      _generateForField(field, queryType);
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
      // fragment generation. The GitLab schema has `relay: Query!` as a Relay
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
            directives: [])
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
        queryType);
    addQueryDefinitionSkipIfExists(def);
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
