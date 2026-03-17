import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_cache_definition.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/utils.dart';

enum GLQueryType { query, mutation, subscription }

class GLQueryDefinition extends GLToken with GLDirectivesMixin {
  final List<GLArgumentDefinition> arguments;
  final List<GLQueryElement> elements;
  final GLQueryType type; //query|mutation|subscription
  GLCacheDefinition? _cacheDefinition;
  Set<GLFragmentDefinitionBase>? _allFrags;

  GLTypeDefinition? _gqTypeDefinition;

  set cacheDefinition(GLCacheDefinition? cacheDefinition) {
    _cacheDefinition = cacheDefinition;
    for (var e in elements) {
      e.cacheDefinition ??= cacheDefinition;
    }
  }

  GLCacheDefinition? get cacheDefinition => _cacheDefinition;

  Set<String> get fragmentNames {
    return elements.expand((e) => e.fragmentNames).toSet();
  }

  Set<GLFragmentDefinitionBase> fragments(GLGrammar g) {
    if (_allFrags == null) {
      var frags = fragmentNames.map((e) => g.getFragmentByName(e)).where((e) => e != null).map((e) => e!).toSet();
      _allFrags = {...frags, ...frags.expand((e) => e.dependecies)};
    }
    return _allFrags!;
  }

  GLQueryDefinition(super.tokenInfo, List<GLDirectiveValue> directives, this.arguments, this.elements, this.type) {
    directives.forEach(addDirective);
    checkVariables();
  }

  void checkVariables() {
    for (var elem in elements) {
      checkElement(elem);
    }
  }

  void checkElement(GLQueryElement element) {
    var list = element.arguments;

    for (var arg in list) {
      if ("${arg.value}".startsWith("\$")) {
        var check = checkValue("${arg.value}");
        if (!check) {
          throw ParseException("Argument ${arg.value} was not declared", info: arg.tokenInfo);
        }
      }
    }
  }

  bool checkValue(String value) {
    for (var arg in arguments) {
      if (arg.token == value) {
        return true;
      }
    }
    return false;
  }

  GLTypeDefinition getGeneratedTypeDefinition() {
    var gqDef = _gqTypeDefinition;
    if (gqDef == null) {
      _gqTypeDefinition = gqDef = GLTypeDefinition(
        name: tokenInfo.ofNewName(_getGeneratedTypeName()),
        nameDeclared: getNameValueFromDirectives(getDirectives()) != null,
        fields: _generateFields(),
        directives: getDirectives(),
        interfaceNames: {},
        derivedFromType: null,
        extension: false,
      );
      gqDef.addDirective(GLDirectiveValue(glInternal.toToken(), [], [], generated: true));
    }
    return gqDef;
  }

  void updateTypeDefinition(GLTypeDefinition def) {
    _gqTypeDefinition = def;
  }

  GLTypeDefinition? get typeDefinition => _gqTypeDefinition;

  String _getGeneratedTypeName() {
    return getNameValueFromDirectives(getDirectives()) ?? "${tokenInfo.token.firstUp}Response";
  }

  List<GLField> _generateFields() {
    return elements
        .map(
          (e) => GLField(
            name: e.alias ?? e.tokenInfo,
            type: e.returnProjectedType,
            arguments: [],
            directives: e.getDirectives(),
          ),
        )
        .toList();
  }

  GLArgumentDefinition findByName(String name) => arguments.where((arg) => arg.token == name).first;
}

class GLQueryElement extends GLToken with GLDirectivesMixin {
  final GLFragmentBlockDefinition? block;

  final List<GLArgumentValue> arguments;
  final TokenInfo? alias;
  GLCacheDefinition? cacheDefinition;

  ///
  ///This is unknown on parse time. It is filled on run time.
  ///
  late final GLType returnType;

  ///
  ///This is unknown on parse time. It is filled on run time.
  ///
  GLTypeDefinition? projectedType;

  String? projectedTypeKey;

  Set<String> get fragmentNames {
    if (block == null) {
      return {};
    }
    return _getFragmentNamesByBlock(block!);
  }

  Set<GLFragmentDefinitionBase> getFragmentsAndDependecies(GLGrammar g) {
    var frags = fragmentNames.map((e) => g.getFragmentByName(e)!).toSet();
    var _allFrags = {...frags, ...frags.expand((e) => e.dependecies)};
    return _allFrags;
  }

  Set<String> _getFragmentNamesByBlock(GLFragmentBlockDefinition block) {
    var set1 =
        block.projections.values.where((element) => element.isFragmentReference).map((e) => e.fragmentName!).toSet();
    var set2 = block.projections.values
        .where((element) => !element.isFragmentReference && element.block != null)
        .map((e) => e.block!)
        .expand((element) => _getFragmentNamesByBlock(element))
        .toSet();
    return {...set1, ...set2};
  }

  GLType _getReturnProjectedType(GLTypeDefinition? projectedType, GLType returnType) {
    if (projectedType == null) {
      return returnType;
    } else {
      if (returnType is GLListType) {
        return GLListType(_getReturnProjectedType(projectedType, returnType.type), returnType.nullable);
      } else {
        return GLType(projectedType.tokenInfo, returnType.nullable);
      }
    }
  }

  GLType get returnProjectedType => _getReturnProjectedType(projectedType, returnType);

  GLQueryElement(super.tokenInfo, List<GLDirectiveValue> directives, this.block, this.arguments, this.alias) {
    directives.forEach(addDirective);
  }

  String get escapedToken {
    var aliasText = alias == null ? '' : "$alias:";
    return "$aliasText$tokenInfo".replaceFirst("\$", "\\\$");
  }

  String get nonEscapedToken {
    var aliasText = alias == null ? '' : "$alias:";
    return "$aliasText$tokenInfo";
  }
}
