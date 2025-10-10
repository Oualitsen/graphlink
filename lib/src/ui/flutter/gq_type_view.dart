import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/utils.dart';

class GQTypeView extends GQToken {
  final GQTypeDefinition type;

  GQTypeView({required this.type}) : super(type.tokenInfo.ofNewName(widgetName(type.token))) {
    addImport('package:flutter/material.dart');
  }

  

  @override
  Set<GQToken> getImportDependecies(GQGrammar g) {
    var result = <GQToken>{};
    result.add(type);
    result.add(g.getTokenByKey('GQFieldViewType')!);
    var fields = type.getSerializableFields(g.mode);
    // grab the enums
    fields
        .where((f) => g.isEnum(f.type.token))
        .forEach((f) => result.add(g.enums[f.type.token]!));
    // grab the widgets
    
    fields
        .where((f) => g.projectedTypes.containsKey(f.type.token))
        .forEach((f) => result.add(g.views[widgetName(f.type.token)]!));

    return result;
  }
}
