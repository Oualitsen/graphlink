import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

class FlutterTypesCompanionSerializer {
  final DartCodeGenUtils _u;
  final GLParser _parser;

  FlutterTypesCompanionSerializer(this._u, this._parser);

  String serializeLabelsClass(String typeName, List<GLField> fields) {
    return _u.createClass(
      className: '${typeName}Labels',
      statements: [
        ...fields.expand((f) => ['final Widget? ${f.codeName};', 'final String? ${f.codeName}Info;']),
        r'final Widget? $group;',
        r'final String? $groupInfo;',
        _u.createMethod(
          isConst: true,
          methodName: '${typeName}Labels',
          namedArguments: true,
          arguments: [
            ...fields.expand((f) => ['this.${f.codeName}', 'this.${f.codeName}Info']),
            r'this.$group',
            r'this.$groupInfo',
          ],
        ),
      ],
    );
  }

  String serializeValuesClass(String typeName, List<GLField> fields) {
    return _u.createClass(
      className: '${typeName}Values',
      statements: [
        ...fields.map((f) => 'final Widget? ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${typeName}Values',
          namedArguments: true,
          arguments: fields.map((f) => 'this.${f.codeName}').toList(),
        ),
      ],
    );
  }

  String serializeVisibilityClass(String typeName, List<GLField> fields) {
    return _u.createClass(
      className: '${typeName}Visibility',
      statements: [
        ...fields.map((f) => 'final bool ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${typeName}Visibility',
          namedArguments: true,
          arguments: fields
              .map((f) => 'this.${f.codeName} = ${f.type.firstType.token == 'ID' ? 'false' : 'true'}')
              .toList(),
        ),
      ],
    );
  }

  String serializeOrderClass(String typeName, List<GLField> fields) {
    return _u.createClass(
      className: '${typeName}Order',
      statements: [
        ...fields.map((f) => 'final int? ${f.codeName};'),
        r'final int? $group;',
        _u.createMethod(
          isConst: true,
          methodName: '${typeName}Order',
          namedArguments: true,
          arguments: [...fields.map((f) => 'this.${f.codeName}'), r'this.$group'],
        ),
      ],
    );
  }

  String serializeShowOnlyClass(String typeName, List<GLField> fields) {
    return _u.createClass(
      className: '${typeName}ShowOnly',
      statements: [
        ...fields.map((f) => 'final bool ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${typeName}ShowOnly',
          namedArguments: true,
          arguments: fields.map((f) => 'this.${f.codeName} = false').toList(),
        ),
        _u.createMethod(
          returnType: '${typeName}Visibility',
          methodName: 'toVisibility',
          namedArguments: false,
          arguments: [],
          statements: [
            'return ${_u.callExpression('${typeName}Visibility', fields.map((f) => '${f.codeName}: ${f.codeName}').toList())};',
          ],
        ),
      ],
    );
  }

  String serializeEnumLabelsClass(String typeName, List<GLField> enumFields) {
    return _u.createClass(
      className: '${typeName}EnumLabels',
      statements: [
        ...enumFields.map((f) => 'final ${_parser.enums[f.type.firstType.token]?.codeName ?? f.type.firstType.token}Labels? ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${typeName}EnumLabels',
          namedArguments: true,
          arguments: enumFields.map((f) => 'this.${f.codeName}').toList(),
        ),
      ],
    );
  }
}
