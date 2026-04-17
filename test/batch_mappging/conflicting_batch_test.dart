import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/spring_server_serializer.dart';
import 'package:test/test.dart';

void main() {
  final typeMapping = {
    "ID": "String",
    "String": "String",
    "Float": "Double",
    "Int": "Integer",
    "Boolean": "Boolean",
  };

  // The mapping key is built from (type + field), NOT from (parent + type + field).
  // When two parent types both reference the same return type with conflicting
  // batch settings, genSchemaMappings generates the same key twice with
  // different batch values — a genuine conflict.
  //
  //   User.record   @glSkipOnServer(batch: true)  → recordDetails(batch: true)
  //   Manager.record @glSkipOnServer(batch: false) → recordDetails(batch: false) ← conflict
  test('conflicting batch settings for the same mapping key throws', () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);

    expect(
      () => g.parse('''
        type Query {
          getUser: User
          getManager: Manager
        }
        type User {
          record: Record @glSkipOnServer(batch: true)
        }
        type Manager {
          record: Record @glSkipOnServer(batch: false)
        }
        type Record {
          details: Details @glSkipOnServer
        }
        type Details {
          id: String
        }
      '''),
      throwsA(isA<ParseException>()),
    );
  });

  // The conflict is resolved by annotating Record.details directly —
  // this explicit value takes priority via typeFieldBatch and prevents ambiguity.
  test('conflict resolved by explicit batch on the field itself', () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      type Query {
        getUser: User
        getManager: Manager
      }
      type User {
        record: Record @glSkipOnServer(batch: true)
      }
      type Manager {
        record: Record @glSkipOnServer(batch: false)
      }
      type Record {
        details: Details @glSkipOnServer(batch: true)
      }
      type Details {
        id: String
      }
    ''');

    final mapping = g.getMappingByName('recordDetails')!;
    expect(mapping.batch, isTrue);

    final serializer = SpringServerSerializer(g);
    final ctrl = g.controllers[g.controllerMappingName('Record')]!;
    expect(serializer.serializeController(ctrl, 'com.example'),
        contains('@BatchMapping'));
  });
}
