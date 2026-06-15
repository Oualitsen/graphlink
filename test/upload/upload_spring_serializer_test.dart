import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  

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
  late JavaSpringServerSerializer serializer;

  setUp(() {
    g = GLParser( mode: CodeGenerationMode.server);
    g.parse(schema);
    serializer = JavaSpringServerSerializer(g, packageName: "");
  });

  group('upload — controller', () {
    test('single upload arg is MultipartFile', () {
      final ctrl = g.controllers['UploadedFileServiceController']!;
      final result = serializer.serializeController(ctrl);
      final lines = result.split('\n').map((e) => e.trim()).toList();

      expect(
        lines,
        containsAllInOrder([
          '@MutationMapping()',
          'public CompletableFuture<${toServerProjectionName('UploadedFile')}> uploadFile(@Argument() MultipartFile file, @Argument() String filename) {',
        ]),
      );
    });

    test('list upload arg is List<MultipartFile>', () {
      final ctrl = g.controllers['UploadedFileServiceController']!;
      final result = serializer.serializeController(ctrl);
      final lines = result.split('\n').map((e) => e.trim()).toList();

      expect(
        lines,
        containsAllInOrder([
          '@MutationMapping()',
          'public CompletableFuture<List<? extends ${toServerProjectionName('UploadedFile')}>> uploadFiles(@Argument() List<MultipartFile> files, @Argument() String label) {',
        ]),
      );
    });

    test('MultipartFile import is present', () {
      final ctrl = g.controllers['UploadedFileServiceController']!;
      final result = serializer.serializeController(ctrl);

      expect(result, contains('import org.springframework.web.multipart.MultipartFile'));
    });
  });

  group('upload — service interface', () {
    test('single upload arg is MultipartFile', () {
      final service = g.services['UploadedFileService']!;
      final result = serializer.serializeService(service);
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
      final result = serializer.serializeService(service);
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
