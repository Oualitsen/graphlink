import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';
import 'package:retrofit_graphql/src/tree/tree.dart';
import 'package:retrofit_graphql/src/utils.dart';

class GQTypedFragment {
  final GQFragmentDefinitionBase fragment;
  final GQTypeDefinition onType;

  GQTypedFragment(this.fragment, this.onType);
}

abstract class GQFragmentDefinitionBase extends GQToken with GQDirectivesMixin {
  final TokenInfo onTypeName;

  final GQFragmentBlockDefinition block;

  final List<GQFragmentDefinitionBase> _dependecies = [];

  GQFragmentDefinitionBase(
    super.tokenInfo,
    this.onTypeName,
    this.block,
    List<GQDirectiveValue> directives,
  ) {
    directives.forEach(addDirective);
  }

  void updateDepencies(Map<String, GQFragmentDefinitionBase> map) {
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

  addDependecy(GQFragmentDefinitionBase fragment) {
    _dependecies.add(fragment);
  }

  Set<GQFragmentDefinitionBase> get dependecies => _dependecies.toSet();

  List get deps => _dependecies;
}

class GQInlineFragmentDefinition extends GQFragmentDefinitionBase {
  GQInlineFragmentDefinition(TokenInfo onTypeName, GQFragmentBlockDefinition block, List<GQDirectiveValue> directives)
      : super(
          "Inline_${generateUuid('_')}".toToken(),
          onTypeName,
          block,
          directives,
        ) {
    if (!block.projections.containsKey(GQGrammar.typename)) {
      block.projections[GQGrammar.typename] = GQProjection(
          fragmentName: null, token: TokenInfo.ofString(GQGrammar.typename), alias: null, block: null, directives: []);
    }
  }

  @override
  String generateName() {
    return "${onTypeName}_$tokenInfo";
  }
}

class GQFragmentDefinition extends GQFragmentDefinitionBase {
  /// can be an interface or a type

  final String fragmentName;

  GQFragmentDefinition(super.token, super.onTypeName, super.block, super.directives) : fragmentName = token.token;

  @override
  String generateName() {
    return "${onTypeName}_$fragmentName";
  }
}

class GQInlineFragmentsProjection extends GQProjection {
  final List<GQInlineFragmentDefinition> inlineFragments;
  GQInlineFragmentsProjection({required this.inlineFragments})
      : super(
          alias: null,
          directives: const [],
          fragmentName: null,
          token: null,
          block: null,
        );
}

class GQProjection extends GQToken with GQDirectivesMixin {
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

  final GQFragmentBlockDefinition? block;

  GQProjection({
    required this.fragmentName,
    required TokenInfo? token,
    required this.alias,
    required this.block,
    required List<GQDirectiveValue> directives,
  }) : super(token ?? TokenInfo.ofString(fragmentName ?? "*")) {
    directives.forEach(addDirective);
  }

  String get actualName => alias?.token ?? targetToken;

  String get targetToken => tokenInfo.token == allFields && fragmentName != null ? fragmentName! : tokenInfo.token;

  getDependecies(Map<String, GQFragmentDefinitionBase> map, TreeNode node) {
    if (isFragmentReference) {
      if (block == null) {
        TreeNode child;

        if (!node.contains(targetToken)) {
          child = node.addChild(targetToken);
        } else {
          throw ParseException("Dependecy Cycle ${[targetToken, ...node.getParents()].join(" -> ")}", info: tokenInfo);
        }

        GQFragmentDefinitionBase? frag = map[targetToken];

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

class GQFragmentBlockDefinition {
  final Map<String, GQProjection> projections = {};

  GQFragmentBlockDefinition(List<GQProjection> projections) {
    for (var element in projections) {
      this.projections[element.token] = element;
    }
  }

  Map<String, GQProjection> getAllProjections(GQGrammar grammar) {
    var result = <String, GQProjection>{};
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

  GQProjection getProjection(TokenInfo token) {
    final p = projections[token.token];
    if (p == null) {
      throw ParseException("Could not find projection with name is ${token.token}", info: token);
    }
    return p;
  }

  void getDependecies(Map<String, GQFragmentDefinitionBase> map, TreeNode node) {
    var projectionList = projections.values;
    for (var projection in projectionList) {
      projection.getDependecies(map, node);
    }
  }

  String? _uniqueName;

  String getUniqueName(GQGrammar g) {
    if (_uniqueName != null) {
      return _uniqueName!;
    }
    final keys = _getKeys(g);
    keys.sort();
    _uniqueName = keys.join("_");
    return _uniqueName!;
  }

  List<String> _getKeys(GQGrammar g) {
    var key = <String>[];
    projections.forEach((k, v) {
      if (k != GQGrammar.typename) {
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

  List<GQProjection> getFragmentReferences() {
    return projections.values.where((projection) => projection.isFragmentReference).toList();
  }
}
