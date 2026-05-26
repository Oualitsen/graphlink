import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_query_element.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/utils.dart';

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
    if (!realType.getSerializableFields(mode)
        .every((f) => resultFieldNames.contains(f.name.token))) {
          return false;
        }
    return result.where((f) => typeRequiresProjection(f.type)).every((f) {
      final sub = projectedTypes[f.type.firstType.token]
               ?? projectedInterfaces[f.type.firstType.token];
      return sub != null && sub.isExhaustive(this);
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
        result.add(_applyProjectionToField(
            field, projection, projection.getDirectives()));
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
      [List<GLDirectiveValue> fieldDirectives = const []]) {
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

      return GLField(
        name: fieldName,
        type: _createTypeFrom(field.type, fieldInlineType),
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
