import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';



GLParser _parser() => GLParser(
      mode: CodeGenerationMode.server,
    );

List<String> _lines(String schema, String inputName,
    {bool inputsAsRecords = true, bool typesAsRecords = true}) {
  final g = _parser()..parse(schema);
  final input = g.inputs[inputName]!;
  final result = JavaSerializer(g,
          inputsAsRecords: inputsAsRecords,
          typesAsRecords: typesAsRecords)
      .serializeInputDefinition(input, '');
  return result.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
}

// ---------------------------------------------------------------------------
// Case: nested input WITHOUT @glMapsTo — must become a required param
// ---------------------------------------------------------------------------

const _unmappedNested = '''
  input PeriodInput {
    value: Int!
    unit: String!
  }

  type Period {
    value: Int!
    unit: String!
  }

  type Equipment {
    id: ID!
    name: String!
    maintenancePeriod: Period!
  }

  input EquipmentInput @glMapsTo(type: "Equipment") {
    name: String!
    maintenancePeriod: PeriodInput!
  }

  type Query { noop: String }
''';

// ---------------------------------------------------------------------------
// Case: field declared as String! in input, ID! in type — both serialize to
// String via typeMap, so the field must be auto-mapped (not a requiredParam).
// ---------------------------------------------------------------------------

const _tokenAlias = '''
  type Ensurer {
    id: ID!
    payerCenterId: ID!
    name: String!
  }

  input EnsurerInput @glMapsTo(type: "Ensurer") {
    payerCenterId: String!
    name: String!
  }

  type Query { noop: String }
''';

// ---------------------------------------------------------------------------
// Case: nested input WITH @glMapsTo — must be auto-mapped via .toPeriod()
// ---------------------------------------------------------------------------

const _mappedNested = '''
  input PeriodInput @glMapsTo(type: "Period") {
    value: Int!
    unit: String!
  }

  type Period {
    value: Int!
    unit: String!
  }

  type Equipment {
    id: ID!
    name: String!
    maintenancePeriod: Period!
  }

  input EquipmentInput @glMapsTo(type: "Equipment") {
    name: String!
    maintenancePeriod: PeriodInput!
  }

  type Query { noop: String }
''';

void main() {
  group('String and ID fields that share a serialized type are auto-mapped', () {
    test('toEnsurer() requires only the missing id param, not payerCenterId', () {
      final lines = _lines(_tokenAlias, 'EnsurerInput');
      expect(lines, contains('public Ensurer toEnsurer(String id) {'));
    });

    test('toEnsurer() passes payerCenterId() directly without conversion', () {
      final lines = _lines(_tokenAlias, 'EnsurerInput');
      final body = lines.join('\n');
      expect(body, contains('payerCenterId()'));
    });
  });


  group('unmapped nested input type becomes requiredParam', () {
    test('toEquipment() signature includes Period maintenancePeriod param', () {
      final lines = _lines(_unmappedNested, 'EquipmentInput');
      expect(lines, contains('public Equipment toEquipment(String id, Period maintenancePeriod) {'));
    });

    test('toEquipment() does not call maintenancePeriod() as an accessor', () {
      final lines = _lines(_unmappedNested, 'EquipmentInput');
      final body = lines.join('\n');
      expect(body, isNot(contains('maintenancePeriod()')));
    });

    test('toEquipment() passes maintenancePeriod param directly to constructor', () {
      final lines = _lines(_unmappedNested, 'EquipmentInput');
      expect(lines, contains('maintenancePeriod'));
    });
  });

  group('mapped nested input type is auto-mapped via .toPeriod()', () {
    test('toEquipment() signature does NOT include a Period maintenancePeriod param', () {
      final lines = _lines(_mappedNested, 'EquipmentInput');
      final signatureLine = lines.firstWhere(
        (l) => l.contains('toEquipment('),
        orElse: () => '',
      );
      expect(signatureLine, isNot(contains('Period maintenancePeriod')));
    });

    test('toEquipment() calls maintenancePeriod().toPeriod()', () {
      final lines = _lines(_mappedNested, 'EquipmentInput');
      final body = lines.join('\n');
      expect(body, contains('maintenancePeriod().toPeriod()'));
    });
  });
}
