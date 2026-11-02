import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';

final restPlaceholder = RegExp(r'\{([^{}]+)\}');

enum RestMethod {
  get,
  post,
  put,
  patch,
  delete;

  String get wireName => name.toUpperCase();

  static RestMethod? parse(String value) {
    for (final method in values) {
      if (method.wireName == value) return method;
    }
    return null;
  }
}

enum RestArgRole { path, query, header, body, field, part }

enum RestEncoding { flat, json, spread }

enum RestResponseKind { json, text, binary, none }

enum RestBodyKind { none, json, raw, form, multipart }

class GLRestArgument {
  final GLArgumentDefinition argument;
  final RestArgRole role;

  /// Placeholder, query key, header name, form field or part name. Null when an input object is spread.
  final String? wireName;

  /// Only set for input-object values sent through a query, form or multipart role.
  final RestEncoding? encoding;

  /// Input field name to wire name, only for spread objects.
  final Map<String, String> spreadFields;

  GLRestArgument({
    required this.argument,
    required this.role,
    required this.wireName,
    this.encoding,
    this.spreadFields = const {},
  });

  String get name => argument.bareName;
}

class GLRestResponse {
  final RestResponseKind kind;
  final List<String> pathSegments;
  final String accept;
  final bool allowsEmptyBody;

  GLRestResponse({
    required this.kind,
    required this.pathSegments,
    required this.accept,
    required this.allowsEmptyBody,
  });
}

class GLRestOperation {
  final GLField field;
  final GLQueryType type;
  final RestMethod method;
  final String path;
  final List<String> placeholders;
  final List<GLRestArgument> arguments;
  final RestBodyKind bodyKind;

  /// True when every argument feeding the body is nullable or has a default: the request may then carry no body.
  final bool bodyIsOptional;
  final GLRestResponse response;
  final String? contentType;

  GLRestOperation({
    required this.field,
    required this.type,
    required this.method,
    required this.path,
    required this.placeholders,
    required this.arguments,
    required this.bodyKind,
    required this.bodyIsOptional,
    required this.response,
    required this.contentType,
  });

  String get name => field.name.token;

  RestResponseKind get responseKind => response.kind;

  List<String> get responsePathSegments => response.pathSegments;

  String get accept => response.accept;

  bool get allowsEmptyBody => response.allowsEmptyBody;

  GLRestArgument? argument(String name) {
    for (final a in arguments) {
      if (a.name == name) return a;
    }
    return null;
  }

  int get cacheTtl => (field.getDirectiveByName(glCache)?.getArgValue(glCacheTTL) as int?) ?? 0;

  List<String> get cacheTags => _tags(glCache);

  bool get staleIfOffline => field.getDirectiveByName(glCache)?.getArgValueAsBool(glCacheArgStaleIfOffline) ?? false;

  List<String> get invalidateTags => _tags(glCacheInvalidate);

  bool get invalidatesAll => field.getDirectiveByName(glCacheInvalidate)?.getArgValueAsBool(glCacheArgAll) ?? false;

  List<String> _tags(String directive) =>
      ((field.getDirectiveByName(directive)?.getArgValue(glCacheTagList) as List?) ?? const []).cast<String>();

  GLOperationKey get key => GLOperationKey(name, type);
}
