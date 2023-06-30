import 'package:retrofit_graphql/src/gq_grammar.dart';

abstract class DartSerializable {
  String toDart(GQGrammar grammar);
}
