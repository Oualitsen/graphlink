import 'package:retrofit_graphql/graphql_parser/gq_grammar.dart';

abstract class DartSerializable {
  String toDart(GQGrammar grammar);
}
