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
    var fieldName = fieldNameToken.token;
    var onType = getType(fieldNameToken.ofNewName(typeName));

    var result =
        onType.fields.where((element) => element.name.token == fieldName);
    if (result.isEmpty && fieldName != GLParser.typename) {
      throw ParseException(
          "Could not find field '$fieldName' on type '$typeName'",
          info: fieldNameToken);
    } else {
      if (result.isNotEmpty) {
        return result.first.type;
      } else {
        return GLType("String".toToken(), false);
      }
    }
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
    var type = getType(fieldToken.ofNewName(typeName));

    var fields = type.fields
        .where((element) => element.name.token == fieldName)
        .toList();
    if (fields.isEmpty) {
      throw ParseException(
          "$typeName does not declare a field with name $fieldName",
          info: type.tokenInfo);
    }
    return fields.first.type;
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
    return field.arguments
        .map((a) => GLArgumentValue(a.tokenInfo, "\$${a.tokenInfo}"))
        .toList();
  }

  GLFragmentDefinition createAllFieldsFragment(
      GLTypeDefinition typeDefinition, Set<String> inProgress) {
    var key = typeDefinition.token;
    var allFieldsKey = GLGrammarExtension.allFieldsFragmentName(key);

    if (typeDefinition is GLInterfaceDefinition) {
      var projection = _createProjectionForInterface(typeDefinition);
      var block = GLFragmentBlockDefinition([projection]);
      return GLFragmentDefinition(
          allFieldsKey.toToken(), typeDefinition.tokenInfo, block, []);
    }

    final projections = typeDefinition.getSerializableFields(mode).map((field) {
      if (typeRequiresProjection(field.type)) {
        final fieldTypeName = field.type.inlineType.token;
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
        GLFragmentBlockDefinition(projections),
        []);
  }

  void createAllFieldsFragments() {
    final allTypes = {...types, ...interfaces};
    final queryTypeNames =
        GLQueryType.values.map((t) => schema.getByQueryType(t)).toSet();

    final Set<String> done = {};
    final Set<String> inProgress = {};

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
  GLFragmentBlockDefinition? _createInlineExpandBlock(
      String typeName, int remainingDepth, Set<String> cycleTypes) {
    final typeDef = types[typeName] ?? interfaces[typeName];
    if (typeDef == null) return null;

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
      return GLProjection(
        fragmentName: null,
        token: field.name,
        alias: null,
        block: _createInlineExpandBlock(fieldTypeName, nextDepth, cycleTypes),
        directives: [],
        arguments: _argumentValuesForField(field),
      );
    }).whereType<GLProjection>().toList();

    return GLFragmentBlockDefinition(projections);
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
    var types = getTypesImplementing(interface);
    var inlineFrags = <GLInlineFragmentDefinition>[];

    types.map((t) {
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
