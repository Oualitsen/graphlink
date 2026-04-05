import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  GLParser parser() =>
      GLParser(autoGenerateQueries: false, generateAllFieldsFragments: false);

  // ---------------------------------------------------------------------------
  // Happy paths
  // ---------------------------------------------------------------------------

  group('valid usage', () {
    test('scalar marked with @glUpload used as a direct mutation argument', () {
      const schema = '''
        scalar Upload $glUpload

        type UploadResult { url: String! }

        type Mutation {
          uploadFile(file: Upload!): UploadResult!
        }

        mutation DoUpload(\$file: Upload!) {
          uploadFile(file: \$file) { url }
        }
      ''';

      expect(() => parser().parse(schema), returnsNormally);
    });

    test('list of upload scalars as a direct mutation argument', () {
      const schema = '''
        scalar Upload $glUpload

        type UploadResult { url: String! }

        type Mutation {
          uploadFiles(files: [Upload!]!): UploadResult!
        }

        mutation DoUpload(\$files: [Upload!]!) {
          uploadFiles(files: \$files) { url }
        }
      ''';

      expect(() => parser().parse(schema), returnsNormally);
    });

    test('upload argument mixed with regular arguments on the same mutation', () {
      const schema = '''
        scalar Upload $glUpload

        type UploadResult { url: String! }

        type Mutation {
          uploadAvatar(file: Upload!, userId: ID!, caption: String): UploadResult!
        }

        mutation DoUpload(\$file: Upload!, \$userId: ID!, \$caption: String) {
          uploadAvatar(file: \$file, userId: \$userId, caption: \$caption) { url }
        }
      ''';

      expect(() => parser().parse(schema), returnsNormally);
    });

    test('upload scalar defined but not used does not throw', () {
      const schema = '''
        scalar Upload $glUpload

        type Query { noop: String }
      ''';

      expect(() => parser().parse(schema), returnsNormally);
    });
  });

  // ---------------------------------------------------------------------------
  // @glUpload placement errors — must only appear on scalars
  // ---------------------------------------------------------------------------

  group('invalid @glUpload placement', () {
    test('throws when @glUpload is placed on a type definition', () {
      const schema = '''
        type Document $glUpload { url: String! }

        type Query { noop: String }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('$glUpload is not allowed on type definitions'),
        )),
      );
    });

    test('throws when @glUpload is placed on an input type', () {
      const schema = '''
        input UploadInput $glUpload { filename: String! }

        type Query { noop: String }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('$glUpload is not allowed on input types'),
        )),
      );
    });

    test('throws when @glUpload is placed on a field', () {
      const schema = '''
        type Document {
          url: String! $glUpload
        }

        type Query { noop: String }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('$glUpload is not allowed on fields'),
        )),
      );
    });

    test('throws when @glUpload is placed on a field argument', () {
      const schema = '''
        type UploadResult { url: String! }

        type Mutation {
          upload(file: String! $glUpload): UploadResult!
        }

        type Query { noop: String }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('$glUpload is not allowed on field arguments'),
        )),
      );
    });

    test('throws when @glUpload is placed on an input field', () {
      const schema = '''
        input UploadInput {
          file: String! $glUpload
        }

        type Query { noop: String }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('$glUpload is not allowed on input fields'),
        )),
      );
    });

    test('throws when @glUpload is placed on a mutation operation', () {
      const schema = '''
        scalar Upload $glUpload

        type UploadResult { url: String! }

        type Mutation {
          uploadFile(file: Upload!): UploadResult!
        }

        mutation DoUpload(\$file: Upload!) $glUpload {
          uploadFile(file: \$file) { url }
        }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('$glUpload is not allowed on operations'),
        )),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Upload scalar usage errors — only valid as direct mutation arguments
  // ---------------------------------------------------------------------------

  group('invalid upload scalar usage', () {
    test('throws when upload scalar is used in an input field', () {
      const schema = '''
        scalar Upload $glUpload

        input UploadInput {
          file: Upload!
        }

        type Query { noop: String }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('is not allowed in input types'),
        )),
      );
    });

    test('throws when upload scalar is used as a type field', () {
      const schema = '''
        scalar Upload $glUpload

        type Document {
          file: Upload!
        }

        type Query { noop: String }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('is not allowed as a field type'),
        )),
      );
    });

    test('throws when upload scalar is used as a Query field argument', () {
      const schema = '''
        scalar Upload $glUpload

        type UploadResult { url: String! }

        type Query {
          findFile(file: Upload!): UploadResult!
        }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('is not allowed as a field argument'),
        )),
      );
    });

    test('throws when upload scalar is used as a regular type field argument', () {
      const schema = '''
        scalar Upload $glUpload

        type Processor {
          process(file: Upload!): String!
        }

        type Query { noop: String }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('is not allowed as a field argument'),
        )),
      );
    });

    test('throws when upload scalar is used as a query operation argument', () {
      const schema = '''
        scalar Upload $glUpload

        type Result { data: String! }

        type Query { noop: String }

        query GetFile(\$file: Upload!) {
          noop
        }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('is not allowed on queries'),
        )),
      );
    });

    test('throws when upload scalar is used as a subscription operation argument', () {
      const schema = '''
        scalar Upload $glUpload

        type FileEvent { url: String! }

        type Subscription {
          fileUploaded: FileEvent!
        }

        type Query { noop: String }

        subscription OnUpload(\$file: Upload!) {
          fileUploaded { url }
        }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('is not allowed on subscriptions'),
        )),
      );
    });

    test('throws when upload scalar is a list of lists in a mutation argument', () {
      const schema = '''
        scalar Upload $glUpload

        type UploadResult { url: String! }

        type Mutation {
          uploadBatch(files: [[Upload!]!]!): UploadResult!
        }

        mutation DoBatch(\$files: [[Upload!]!]!) {
          uploadBatch(files: \$files) { url }
        }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('must be a scalar or a single-level list'),
        )),
      );
    });

    test('throws when list of upload scalars is used in an input field', () {
      const schema = '''
        scalar Upload $glUpload

        input BatchUploadInput {
          files: [Upload!]!
        }

        type Query { noop: String }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('is not allowed in input types'),
        )),
      );
    });
  });
}
