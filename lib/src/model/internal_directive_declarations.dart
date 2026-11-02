import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

const internalDurationScalar = 'GLDuration';
const internalMapScalar = 'GLMap';

const internalDirectiveSdl = '''
# Types used by the directives below
enum GLRestMethod { GET POST PUT PATCH DELETE }
enum GLRestEncoding { FLAT JSON SPREAD }
enum GLRestResponseKind { JSON TEXT BINARY }
scalar GLDuration
scalar GLMap

directive @include(if: Boolean!) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT
directive @skip(if: Boolean!) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT
directive @deprecated(reason: String) on FIELD_DEFINITION | ARGUMENT_DEFINITION | INPUT_FIELD_DEFINITION | ENUM_VALUE
directive @specifiedBy(url: String!) on SCALAR
directive @oneOf on INPUT_OBJECT

# Caching
directive @glCache(ttl: GLDuration, tags: [String!], staleIfOffline: Boolean) on FIELD | FIELD_DEFINITION | QUERY | MUTATION | SUBSCRIPTION
directive @glCacheInvalidate(all: Boolean, tags: [String!]) on FIELD | FIELD_DEFINITION | QUERY | MUTATION | SUBSCRIPTION
directive @glNoCache on FIELD | FIELD_DEFINITION | QUERY | MUTATION | SUBSCRIPTION

# Code generation control
directive @glCaptureErrors on FIELD_DEFINITION | QUERY | MUTATION
directive @glDecorators(value: [String!]!, applyOnClient: Boolean, applyOnServer: Boolean, glImport: String) repeatable on ENUM | ENUM_VALUE | FIELD_DEFINITION | INPUT_FIELD_DEFINITION | INPUT_OBJECT | INTERFACE | OBJECT | SCALAR | UNION | ARGUMENT_DEFINITION
directive @glEqualsHashcode(fields: [String!]) on FIELD | OBJECT | INPUT_OBJECT | INTERFACE
directive @glExpand(depth: Int) on OBJECT
directive @glExternal(glClass: String, glImport: String) on INPUT_OBJECT | OBJECT | SCALAR | INTERFACE
directive @glInjectContext on FIELD_DEFINITION
directive @glIntercept(tag: String) on FIELD_DEFINITION | INPUT_FIELD_DEFINITION | OBJECT
directive @glMapField(to: String!) on INPUT_FIELD_DEFINITION
directive @glMapsTo(type: String!) on INPUT_OBJECT
directive @glRepository(glType: String, glIdType: String) on INTERFACE | OBJECT
directive @glServerLenient on OBJECT
directive @glServiceName(name: String!) on ENUM | FIELD_DEFINITION | INPUT_OBJECT | INTERFACE | OBJECT
directive @glSkipOnClient on ENUM | ENUM_VALUE | FIELD_DEFINITION | INPUT_FIELD_DEFINITION | INPUT_OBJECT | INTERFACE | OBJECT | SCALAR | UNION
directive @glSkipOnServer(batch: Boolean, mapTo: String) on ENUM | ENUM_VALUE | FIELD_DEFINITION | INPUT_FIELD_DEFINITION | INPUT_OBJECT | INTERFACE | OBJECT | SCALAR | UNION
directive @glTypeName(name: String!) on FIELD | INLINE_FRAGMENT | FRAGMENT_DEFINITION | INPUT_OBJECT | QUERY | MUTATION | SUBSCRIPTION
directive @glUpload on SCALAR
directive @glValidate on FIELD_DEFINITION
directive @glInternal on OBJECT | INTERFACE | ENUM | INPUT_OBJECT | SCALAR
directive @glInterfaceFieldAsProperties on INTERFACE


# REST operations
directive @glRest(path: String, method: GLRestMethod, contentType: String, accept: String, response: GLRestResponseKind, responsePath: String) on FIELD_DEFINITION
directive @glRestPrefix(path: String, method: GLRestMethod) repeatable on OBJECT
directive @glRestPath(name: String) on ARGUMENT_DEFINITION
directive @glRestParam(name: String, encoding: GLRestEncoding) on ARGUMENT_DEFINITION | INPUT_FIELD_DEFINITION
directive @glRestHeader(name: String) on ARGUMENT_DEFINITION | INPUT_FIELD_DEFINITION | INPUT_OBJECT
directive @glRestBody on ARGUMENT_DEFINITION
directive @glRestField(name: String, encoding: GLRestEncoding) on ARGUMENT_DEFINITION | INPUT_FIELD_DEFINITION
directive @glRestPart(name: String, encoding: GLRestEncoding) on ARGUMENT_DEFINITION | INPUT_FIELD_DEFINITION
directive @glRestDiscriminator(field: String!, values: GLMap) on INTERFACE | UNION
directive @glDownload on SCALAR
directive @glVoid on SCALAR
''';

const _toolKnownDirectives = {'@include', '@skip', '@deprecated', '@specifiedBy'};

String directiveDeclarationsForIde() {
  final blocks = internalDirectiveSdl.trim().split(RegExp(r'\n\s*\n'));
  final kept = [
    for (final block in blocks)
      [
        for (final line in block.split('\n'))
          if (!_toolKnownDirectives.any((d) => line.startsWith('directive $d('))) line,
      ].join('\n'),
  ].where((b) => b.trim().isNotEmpty);
  return '# GraphLink directive declarations, for your IDE and GraphQL tooling.\n'
      '# Keep this file out of the schemaPaths of glink.json: GraphLink already knows these directives.\n\n'
      '${kept.join('\n\n')}\n';
}

class InternalDirectives {
  final Map<String, GLDirectiveDefinition> definitions;
  final Map<String, GLEnumDefinition> enums;

  InternalDirectives._(this.definitions, this.enums);

  static final InternalDirectives instance = _load();

  static InternalDirectives _load() {
    final parser = GLParser()..parse(internalDirectiveSdl, validate: false);
    return InternalDirectives._(
      Map.unmodifiable(parser.directiveDefinitions),
      Map.unmodifiable(parser.enums),
    );
  }
}
