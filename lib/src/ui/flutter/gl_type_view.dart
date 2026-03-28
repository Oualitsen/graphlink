import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/utils.dart';

class GLTypeView extends GLToken {
  final GLTypeDefinition type;

  GLTypeView({required this.type})
      : super(type.tokenInfo.ofNewName(widgetName(type.token))) {
    addImport('package:flutter/material.dart');
  }

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    var result = <GLToken>{};
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
