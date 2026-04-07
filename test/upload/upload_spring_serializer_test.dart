import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/language.dart';
import 'package:graphlink/src/serializers/spring_server_serializer.dart';
import 'package:test/test.dart';

void main() {
  final typeMapping = {
    "ID": "String",
    "String": "String",
    "Float": "Double",
    "Int": "Integer",
    "Boolean": "Boolean",
    "Null": "null",
  };

  const schema = '''
    directive $glUpload on SCALAR

    scalar Upload $glUpload

    type UploadedFile {
      id: ID!
      url: String!
    }

    type Mutation {
      uploadFile(file: Upload!, filename: String!): UploadedFile!
      uploadFiles(files: [Upload!]!, label: String): [UploadedFile!]!
    }

    type Query { noop: String }
  ''';

  late GLParser g;
  late SpringServerSerializer serializer;

  setUp(() {
    g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse(schema);
    serializer = SpringServerSerializer(g);
  });

  group('upload — controller', () {
    test('single upload arg is MultipartFile', () {
      final ctrl = g.controllers['UploadedFileServiceController']!;
      final result = serializer.serializeController(ctrl, 'com.example');
      final lines = result.split('\n').map((e) => e.trim()).toList();

      expect(
        lines,
        containsAllInOrder([
          '@MutationMapping()',
          'public CompletableFuture<UploadedFile> uploadFile(@Argument() MultipartFile file, @Argument() String filename) {',
        ]),
      );
    });

    test('list upload arg is List<MultipartFile>', () {
      final ctrl = g.controllers['UploadedFileServiceController']!;
      final result = serializer.serializeController(ctrl, 'com.example');
      final lines = result.split('\n').map((e) => e.trim()).toList();

      expect(
        lines,
        containsAllInOrder([
          '@MutationMapping()',
          'public CompletableFuture<List<UploadedFile>> uploadFiles(@Argument() List<MultipartFile> files, @Argument() String label) {',
        ]),
      );
    });

    test('MultipartFile import is present', () {
      final ctrl = g.controllers['UploadedFileServiceController']!;
      final result = serializer.serializeController(ctrl, 'com.example');

      expect(result, contains('import org.springframework.web.multipart.MultipartFile'));
    });
  });

  group('upload — service interface', () {
    test('single upload arg is MultipartFile', () {
      final service = g.services['UploadedFileService']!;
      final result = serializer.serializeService(service, 'com.example');
      final lines = result.split('\n').map((e) => e.trim()).toList();

      expect(
        lines,
        containsAllInOrder([
          'UploadedFile uploadFile(MultipartFile file, String filename);',
        ]),
      );
    });

    test('list upload arg is List<MultipartFile>', () {
      final service = g.services['UploadedFileService']!;
      final result = serializer.serializeService(service, 'com.example');
      final lines = result.split('\n').map((e) => e.trim()).toList();

      expect(
        lines,
        containsAllInOrder([
          'List<UploadedFile> uploadFiles(List<MultipartFile> files, String label);',
        ]),
      );
    });
  });
}
