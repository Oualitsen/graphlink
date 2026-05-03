import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/graphq_serializer.dart';
import 'package:test/test.dart';

void main() {
  const schema = '''
    type Query {
      getTotalRooms: Int!
      getTotalPositions: Int!
      getTotalHemodialysisGroup: Int!
      getTotalTransportationCompany: Int!
    }

    query GetSetupStatus {
      totalRooms: getTotalRooms
      totalPositions: getTotalPositions
      totalHemodialysisGroups: getTotalHemodialysisGroup
      totalTransportationCompanies: getTotalTransportationCompany
    }
  ''';

  test('serializeQueryDefinition - aliased scalar fields', () {
    final parser = GLParser();
    parser.parse(schema);

    final def = parser.queries['GetSetupStatus']!;
    final serializer = GLGraphqSerializer(parser);
    final result = serializer.serializeQueryDefinition(def);

    print('serializeQueryDefinition:\n$result');
  });

  test('divideQueryDefinition - no adjacent fields without space', () {
    final parser = GLParser();
    parser.parse(schema);

    final def = parser.queries['GetSetupStatus']!;
    final serializer = GLGraphqSerializer(parser);
    final divided = serializer.divideQueryDefinition(def, parser);

    print('divided queries:');
    for (final dq in divided) {
      print('  elementKey=${dq.elementKey}  query="${dq.query}"');
    }

    final joined = divided.map((e) => e.query).join(' ');
    print('joined: $joined');

    for (final dq in divided) {
      expect(dq.query, isNot(contains('getTotalRoomstotal')));
    }
  });
}
