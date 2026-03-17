import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/tree/tree.dart';
import 'package:graphlink/src/utils.dart';

class GLTypedFragment {
  final GLFragmentDefinitionBase fragment;
  final GLTypeDefinition onType;

  GLTypedFragment(this.fragment, this.onType);
}

abstract class GLFragmentDefinitionBase extends GLToken with GLDirectivesMixin {
  final TokenInfo onTypeName;

  final GLFragmentBlockDefinition block;

  final List<GLFragmentDefinitionBase> _dependecies = [];

  GLFragmentDefinitionBase(
    super.tokenInfo,
    this.onTypeName,
    this.block,
    List<GLDirectiveValue> directives,
  ) {
    directives.forEach(addDirective);
  }

  void updateDepencies(Map<String, GLFragmentDefinitionBase> map) {
    var rootNode = TreeNode(value: tokenInfo.token);
    block.getDependecies(map, rootNode);
    var dependecyNames = rootNode.getAllValues(true).toSet();

    for (var name in dependecyNames) {
      final def = map[name];
      if (def == null) {
        throw ParseException("Fragment $name is not defined", info: tokenInfo);
      }
      _dependecies.add(def);
    }
  }

  String generateName();

  addDependecy(GLFragmentDefinitionBase fragment) {
    _dependecies.add(fragment);
  }

  Set<GLFragmentDefinitionBase> get dependecies => _dependecies.toSet();

  List get deps => _dependecies;
}

class GLInlineFragmentDefinition extends GLFragmentDefinitionBase {
  GLInlineFragmentDefinition(TokenInfo onTypeName, GLFragmentBlockDefinition block, List<GLDirectiveValue> directives)
      : super(
          "Inline_${generateUuid('_')}".toToken(),
          onTypeName,
          block,
          directives,
        ) {
    if (!block.projections.containsKey(GLGrammar.typename)) {
      block.projections[GLGrammar.typename] = GLProjection(
          fragmentName: null, token: TokenInfo.ofString(GLGrammar.typename), alias: null, block: null, directives: []);
    }
  }

  @override
  String generateName() {
    return "${onTypeName}_$tokenInfo";
  }
}

class GLFragmentDefinition extends GLFragmentDefinitionBase {
  /// can be an interface or a type

  final String fragmentName;

  GLFragmentDefinition(super.token, super.onTypeName, super.block, super.directives) : fragmentName = token.token;

  @override
  String generateName() {
    return "${onTypeName}_$fragmentName";
  }
}

class GLInlineFragmentsProjection extends GLProjection {
  final List<GLInlineFragmentDefinition> inlineFragments;
  GLInlineFragmentsProjection({required this.inlineFragments})
      : super(
          alias: null,
          directives: const [],
          fragmentName: null,
          token: null,
          block: null,
        );
}

class GLProjection extends GLToken with GLDirectivesMixin {
  ///
  ///This contains a reference to the fragment name containing this projection
  ///
  ///something like  ... fragmentName

  ///
  String? fragmentName;

  ///
  ///This should contain the name of the type this projection is on
  ///
  final TokenInfo? alias;

  ///
  ///  something like  ... fragmentName
  ///
  bool get isFragmentReference => fragmentName != null;

  ///
  ///  something like
  ///  ... on Entity {
  ///   id creationDate ...
  ///  }
  ///

  final GLFragmentBlockDefinition? block;

  GLProjection({
    required this.fragmentName,
    required TokenInfo? token,
    required this.alias,
    required this.block,
    required List<GLDirectiveValue> directives,
  }) : super(token ?? TokenInfo.ofString(fragmentName ?? "*")) {
    directives.forEach(addDirective);
  }

  String get actualName => alias?.token ?? targetToken;

  String get targetToken => tokenInfo.token == allFields && fragmentName != null ? fragmentName! : tokenInfo.token;

  getDependecies(Map<String, GLFragmentDefinitionBase> map, TreeNode node) {
    if (isFragmentReference) {
      if (block == null) {
        TreeNode child;

        if (!node.contains(targetToken)) {
          child = node.addChild(targetToken);
        } else {
          throw ParseException("Dependecy Cycle ${[targetToken, ...node.getParents()].join(" -> ")}", info: tokenInfo);
        }

        GLFragmentDefinitionBase? frag = map[targetToken];

        if (frag == null) {
          throw ParseException("Fragment $tokenInfo is not defined", info: tokenInfo);
        } else {
          frag.block.getDependecies(map, child);
        }
      } else {
        ///
        ///This should be an inline fragment
        ///

        var myBlock = block;
        if (myBlock == null) {
          throw ParseException("Inline Fragment must have a body", info: tokenInfo);
        }
        myBlock.getDependecies(map, node);
      }
    }
    if (block != null) {
      var children = block!.projections.values;
      for (var projection in children) {
        projection.getDependecies(map, node);
      }
    }
  }
}

class GLFragmentBlockDefinition {
  final Map<String, GLProjection> projections = {};

  GLFragmentBlockDefinition(List<GLProjection> projections) {
    for (var element in projections) {
      this.projections[element.token] = element;
    }
  }

  Map<String, GLProjection> getAllProjections(GLGrammar grammar) {
    var result = <String, GLProjection>{};
    projections.forEach((key, value) {
      if (value.isFragmentReference) {
        var frag = grammar.getFragment(key, value.tokenInfo);
        var fragProjections = frag.block.getAllProjections(grammar);
        result.addAll(fragProjections);
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  GLProjection getProjection(TokenInfo token) {
    final p = projections[token.token];
    if (p == null) {
      throw ParseException("Could not find projection with name is ${token.token}", info: token);
    }
    return p;
  }

  void getDependecies(Map<String, GLFragmentDefinitionBase> map, TreeNode node) {
    var projectionList = projections.values;
    for (var projection in projectionList) {
      projection.getDependecies(map, node);
    }
  }

  String? _uniqueName;

  String getUniqueName(GLGrammar g) {
    if (_uniqueName != null) {
      return _uniqueName!;
    }
    final keys = _getKeys(g);
    keys.sort();
    _uniqueName = keys.join("_");
    return _uniqueName!;
  }

  List<String> _getKeys(GLGrammar g) {
    var key = <String>[];
    projections.forEach((k, v) {
      if (k != GLGrammar.typename) {
        if (v.isFragmentReference) {
          var frag = g.getFragment(v.targetToken, v.tokenInfo);
          var currKey = frag.block._getKeys(g);
          key.addAll(currKey);
        } else {
          key.add(k);
        }
      }
    });
    return key;
  }

  List<GLProjection> getFragmentReferences() {
    return projections.values.where((projection) => projection.isFragmentReference).toList();
  }
}
