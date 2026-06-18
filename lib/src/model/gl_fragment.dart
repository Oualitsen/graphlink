import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/token_info.dart';
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

  bool _dependeciesUpdated = false;

  GLFragmentDefinitionBase(
    super.tokenInfo,
    this.onTypeName,
    this.block,
    List<GLDirectiveValue> directives,
  ) {
    directives.forEach(addDirective);
  }

  void updateDepencies(Map<String, GLFragmentDefinitionBase> map) {
    if (_dependeciesUpdated) return;
    for (final name in block.getDependecies()) {
      final def = map[name];
      if (def == null) {
        throw ParseException("Fragment $name is not defined", info: tokenInfo);
      }
      _dependecies.add(def);
    }
    _dependeciesUpdated = true;
  }

  String generateName();

  addDependecy(GLFragmentDefinitionBase fragment) {
    _dependecies.add(fragment);
  }

  Set<GLFragmentDefinitionBase> get dependecies => _dependecies.toSet();

  List get deps => _dependecies;
}

class GLInlineFragmentDefinition extends GLFragmentDefinitionBase {
  GLInlineFragmentDefinition(TokenInfo onTypeName,
      GLFragmentBlockDefinition block, List<GLDirectiveValue> directives)
      : super(
          "Inline_${generateUuid('_')}".toToken(),
          onTypeName,
          block,
          directives,
        ) {
    if (!block.projections.containsKey(GLParser.typename)) {
      block.projections[GLParser.typename] = GLProjection(
          fragmentName: null,
          token: TokenInfo.ofString(GLParser.typename),
          alias: null,
          block: null,
          directives: []);
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

  GLFragmentDefinition(
      super.token, super.onTypeName, super.block, super.directives)
      : fragmentName = token.token;

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

  ///
  ///  Argument values applied to this field selection, e.g.
  ///  `lastArticles(limit: $limit)` → `[limit: $limit]`
  ///
  final List<GLArgumentValue> arguments;

  GLProjection({
    required this.fragmentName,
    required TokenInfo? token,
    required this.alias,
    required this.block,
    required List<GLDirectiveValue> directives,
    this.arguments = const [],
  }) : super(token ?? TokenInfo.ofString(fragmentName ?? "*")) {
    directives.forEach(addDirective);
  }

  String get actualName => alias?.token ?? targetToken;

  String get targetToken => tokenInfo.token == allFields && fragmentName != null
      ? fragmentName!
      : tokenInfo.token;

  Set<String>? _cachedDependencies;

  Set<String> getDependecies() {
    if (_cachedDependencies != null) return _cachedDependencies!;
    _cachedDependencies = {};
    if (isFragmentReference) {
      if (block == null) {
        _cachedDependencies!.add(targetToken);
      } else {
        _cachedDependencies!.addAll(block!.getDependecies());
      }
    }
    if (block != null) {
      for (var projection in block!.projections.values) {
        _cachedDependencies!.addAll(projection.getDependecies());
      }
    }
    return _cachedDependencies!;
  }
}

class GLFragmentBlockDefinition {
  final Map<String, GLProjection> projections = {};

  /// Set to true after this block has been fully validated. Shared blocks
  /// (non-cyclic types stored in GlFragmentBlockCache) are only validated once.
  bool validated = false;

  GLFragmentBlockDefinition(List<GLProjection> projections) {
    for (var element in projections) {
      this.projections[element.token] = element;
    }
  }

  Map<String, GLProjection> getAllProjections(GLParser grammar) {
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
      throw ParseException(
          "Could not find projection with name is ${token.token}",
          info: token);
    }
    return p;
  }

  Set<String>? _cachedDependencies;

  Set<String> getDependecies() {
    if (_cachedDependencies != null) return _cachedDependencies!;
    // Sentinel: set empty set before recursing so cycles terminate instead of
    // looping infinitely (cycles are caught earlier by checkFragmentRefs).
    _cachedDependencies = {};
    for (var projection in projections.values) {
      _cachedDependencies!.addAll(projection.getDependecies());
    }
    return _cachedDependencies!;
  }

  String? _uniqueName;

  String getUniqueName(GLParser g) {
    if (_uniqueName != null) {
      return _uniqueName!;
    }
    final keys = _getKeys(g);
    keys.sort();
    _uniqueName = keys.join("_");
    return _uniqueName!;
  }

  List<String> _getKeys(GLParser g) {
    var key = <String>[];
    projections.forEach((k, v) {
      if (k != GLParser.typename) {
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
    return projections.values
        .where((projection) => projection.isFragmentReference)
        .toList();
  }
}

/// Shared cache for inline-expanded blocks built by `_createInlineExpandBlock`.
/// Keyed by type name; only non-cyclic types are stored (cyclic types depend on
/// remainingDepth and are never cached). One instance lives for the duration of
/// `createAllFieldsFragments` so blocks are reused across all fragment builds.
class GlFragmentBlockCache {
  final Map<String, GLFragmentBlockDefinition?> _cache = {};

  bool containsKey(String typeName) => _cache.containsKey(typeName);

  GLFragmentBlockDefinition? operator [](String typeName) => _cache[typeName];

  void operator []=(String typeName, GLFragmentBlockDefinition? block) {
    _cache[typeName] = block;
  }
}
