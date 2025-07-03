import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_has_directives.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/tree/tree.dart';
import 'package:retrofit_graphql/src/utils.dart';

class GQTypedFragment {
  final GQFragmentDefinitionBase fragment;
  final GQTypeDefinition onType;

  GQTypedFragment(this.fragment, this.onType);
}

abstract class GQFragmentDefinitionBase extends GQToken with GqHasDirectives {
  final String onTypeName;

  final GQFragmentBlockDefinition block;
  final List<GQDirectiveValue> directives;

  final List<GQFragmentDefinitionBase> _dependecies = [];

  GQFragmentDefinitionBase(
    super.token,
    this.onTypeName,
    this.block,
    this.directives,
  );

  void updateDepencies(Map<String, GQFragmentDefinitionBase> map) {
    var rootNode = TreeNode(value: token);
    block.getDependecies(map, rootNode);
    var dependecyNames = rootNode.getAllValues(true).toSet();

    for (var name in dependecyNames) {
      final def = map[name];
      if (def == null) {
        throw ParseException("Fragment $name is not defined");
      }
      _dependecies.add(def);
    }
  }

  String generateName();

  addDependecy(GQFragmentDefinitionBase fragment) {
    _dependecies.add(fragment);
  }

  Set<GQFragmentDefinitionBase> get dependecies => _dependecies.toSet();

  @override
  List<GQDirectiveValue> getDirectives() {
    return [...directives];
  }
}

class GQInlineFragmentDefinition extends GQFragmentDefinitionBase {
  GQInlineFragmentDefinition(String onTypeName, GQFragmentBlockDefinition block,
      List<GQDirectiveValue> directives)
      : super(
          "Inline_${generateUuid('_')}",
          onTypeName,
          block,
          directives,
        ) {
    if (!block.projections.containsKey(GQGrammar.typename)) {
      block.projections[GQGrammar.typename] = GQProjection(
          fragmentName: null,
          token: GQGrammar.typename,
          alias: null,
          block: null,
          directives: []);
    }
  }

  @override
  String serialize() {
    return """... on $onTypeName ${directives.map((e) => e.serialize()).join(" ")} ${block.serialize()} """;
  }

  @override
  String generateName() {
    return "${onTypeName}_$token";
  }
}

class GQFragmentDefinition extends GQFragmentDefinitionBase {
  /// can be an interface or a type

  final String fragmentName;

  GQFragmentDefinition(this.fragmentName, String onTypeName,
      GQFragmentBlockDefinition block, List<GQDirectiveValue> directives)
      : super(fragmentName, onTypeName, block, directives);

  @override
  String toString() {
    return serialize();
  }

  @override
  String serialize() {
    return """fragment $fragmentName on $onTypeName${serializeDirectives(directives)}${block.serialize()}""";
  }

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

class GQProjection extends GQToken {
  ///
  ///This contains a reference to the fragment name containing this projection
  ///
  ///something like  ... fragmentName

  ///
  String? fragmentName;

  ///
  ///This should contain the name of the type this projection is on
  ///
  final String? alias;

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

  final List<GQDirectiveValue> directives;

  GQProjection({
    required this.fragmentName,
    required String? token,
    required this.alias,
    required this.block,
    required this.directives,
  }) : super(token ?? fragmentName ?? "*");

  @override
  String toString() {
    return serialize();
  }

  String get actualName => alias ?? targetToken;

  @override
  String serialize() {
    if (this is GQInlineFragmentsProjection) {
      return serializeList(
          (this as GQInlineFragmentsProjection).inlineFragments,
          join: " ",
          withParenthesis: false);
    }
    String result = "";
    if (isFragmentReference) {
      result = "...";
    }
    if (alias != null) {
      result += "$alias:$targetToken";
    } else {
      result += targetToken;
    }
    result += serializeDirectives(directives);

    result += block?.serialize() ?? '';

    return result;
  }

  String get targetToken =>
      token == allFields && fragmentName != null ? fragmentName! : token;

  getDependecies(Map<String, GQFragmentDefinitionBase> map, TreeNode node) {
    if (isFragmentReference) {
      if (block == null) {
        TreeNode child;

        if (!node.contains(targetToken)) {
          child = node.addChild(targetToken);
        } else {
          throw ParseException("Dependecy Cycle ${[
            targetToken,
            ...node.getParents()
          ].join(" -> ")}");
        }

        GQFragmentDefinitionBase? frag = map[targetToken];

        if (frag == null) {
          throw ParseException("Fragment $token is not defined");
        } else {
          frag.block.getDependecies(map, child);
        }
      } else {
        ///
        ///This should be an inline fragment
        ///

        var myBlock = block;
        if (myBlock == null) {
          throw ParseException("Inline Fragment must have a body");
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
        var frag = grammar.getFragment(key);
        var fragProjections = frag.block.getAllProjections(grammar);
        result.addAll(fragProjections);
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  GQProjection getProjection(String name) {
    final p = projections[name];
    if (p == null) {
      throw ParseException("Could not find projection with name is $name");
    }
    return p;
  }

  String serialize() {
    return """{${serializeList(projections.values.toList(), join: " ", withParenthesis: false)}}""";
  }

  @override
  String toString() {
    return serialize();
  }

  void getDependecies(
      Map<String, GQFragmentDefinitionBase> map, TreeNode node) {
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
          var frag = g.getFragment(v.targetToken);
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
    return projections.values
        .where((projection) => projection.isFragmentReference)
        .toList();
  }
}
